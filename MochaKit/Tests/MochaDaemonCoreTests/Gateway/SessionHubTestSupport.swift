import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

struct UnexpectedMessage: Error, CustomStringConvertible {
    let message: ServerMessage

    var description: String {
        "unexpected \(message)"
    }
}

func eventually<T>(timeout: Duration = .seconds(5), _ probe: () async -> T?) async throws -> T {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
        if let value = await probe() {
            return value
        }
        guard ContinuousClock.now < deadline else { throw TestTimeoutError() }
        try await Task.sleep(for: .milliseconds(2))
    }
}

final class ManualClock: GatewayClock {
    private struct Sleeper {
        let id: UUID
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var elapsed: Duration = .zero
        var sleepers: [Sleeper] = []
        var cancelled: Set<UUID> = []
    }

    private enum Registration {
        case waiting
        case cancelled
        case due
    }

    let origin: Date
    private let state = Mutex(State())

    init(origin: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        self.origin = origin
    }

    func now() -> Date {
        let elapsed = state.withLock { $0.elapsed }
        return origin.addingTimeInterval(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let registration = state.withLock { state -> Registration in
                    if state.cancelled.remove(id) != nil || Task.isCancelled { return .cancelled }
                    guard duration > .zero else { return .due }
                    state.sleepers.append(Sleeper(id: id, deadline: state.elapsed + duration, continuation: continuation))
                    return .waiting
                }
                switch registration {
                case .waiting: break
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .due: continuation.resume()
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    var pendingDelays: [Duration] {
        state.withLock { state in state.sleepers.map { $0.deadline - state.elapsed } }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.elapsed += duration
            let due = state.sleepers.filter { $0.deadline <= state.elapsed }.sorted { $0.deadline < $1.deadline }
            state.sleepers.removeAll { $0.deadline <= state.elapsed }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    func waitForSleepers(_ count: Int) async throws {
        _ = try await eventually { sleeperCount >= count ? true : nil }
    }
}

final class TestClientSocket: GatewaySocket {
    private struct State {
        var received: [ServerEnvelope] = []
        var cursor = 0
        var closeCode: WebSocketCloseCode?
    }

    let incoming: AsyncStream<WebSocketMessage>
    private let continuation: AsyncStream<WebSocketMessage>.Continuation
    private let state = Mutex(State())

    init() {
        let (incoming, continuation) = AsyncStream.makeStream(of: WebSocketMessage.self)
        self.incoming = incoming
        self.continuation = continuation
    }

    func send(text: String) async throws {
        let envelope = try JSONDecoder().decode(ServerEnvelope.self, from: Data(text.utf8))
        state.withLock { $0.received.append(envelope) }
    }

    func close(code: WebSocketCloseCode, reason: String) async {
        state.withLock { $0.closeCode = code }
        continuation.finish()
    }

    func deliver(_ message: ClientMessage, id: String) throws {
        let data = try JSONEncoder().encode(ClientEnvelope(id: id, message: message))
        continuation.yield(.text(String(decoding: data, as: UTF8.self)))
    }

    func deliverRaw(_ text: String) {
        continuation.yield(.text(text))
    }

    func disconnect() {
        continuation.finish()
    }

    func next() async throws -> ServerEnvelope {
        try await eventually {
            state.withLock { state -> ServerEnvelope? in
                guard state.cursor < state.received.count else { return nil }
                defer { state.cursor += 1 }
                return state.received[state.cursor]
            }
        }
    }

    func nextMessage() async throws -> ServerMessage {
        try await next().message
    }

    func request(_ message: ClientMessage, id: String = "c-1") async throws -> ServerEnvelope {
        try deliver(message, id: id)
        return try await next()
    }

    func reply(to message: ClientMessage, id: String = "c-1") async throws -> ServerMessage {
        let envelope = try await request(message, id: id)
        #expect(envelope.id == id)
        return envelope.message
    }

    func nextMessage(matching predicate: (ServerMessage) -> Bool) async throws -> ServerMessage {
        while true {
            let message = try await nextMessage()
            if predicate(message) {
                return message
            }
        }
    }

    var pendingCount: Int {
        state.withLock { $0.received.count - $0.cursor }
    }

    var receivedMessages: [ServerMessage] {
        state.withLock { $0.received.map(\.message) }
    }

    var initialTree: [WorkspaceNode]? {
        for message in receivedMessages {
            if case .tree(let workspaces) = message {
                return workspaces
            }
        }
        return nil
    }

    var closeCode: WebSocketCloseCode? {
        state.withLock { $0.closeCode }
    }

    func waitForClose() async throws -> WebSocketCloseCode {
        try await eventually { closeCode }
    }
}

enum Sample {
    static let sessionA = "0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64"
    static let sessionB = "5c1e9a7b-4d2f-4b8a-9e3c-6f0a2d8b1c47"
    static let sessionC = "e7a3c9f1-5b2d-4f8e-a1c6-3d9b0f7e2a54"
    static let pairingURL = URL(string: "wss://mac.example.ts.net/v1")!
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func agent(
        _ id: AgentID,
        status: AgentStatus = .idle,
        sessionId: String? = nil,
        kind: String = "claude",
        title: String = "Claude Code",
        workspaceLabel: String = "Core",
        branch: String? = nil
    ) -> AgentSummary {
        AgentSummary(
            id: id,
            kind: kind,
            status: status,
            title: title,
            workspaceLabel: workspaceLabel,
            branch: branch,
            sessionId: sessionId
        )
    }

    static func workspace(
        _ id: WorkspaceID,
        label: String = "Core",
        number: Int = 1,
        tabs: [TabNode],
        children: [WorkspaceNode] = []
    ) -> WorkspaceNode {
        WorkspaceNode(
            id: id,
            label: label,
            number: number,
            isDirty: false,
            agentStatus: HerdrTreeBuilder.aggregateStatus(tabs.flatMap { $0.agents.map(\.status) }),
            tabs: tabs,
            children: children
        )
    }

    static func herdrAgents(in tree: [WorkspaceNode]) -> [HerdrAgent] {
        tree.flatMap { workspace in
            workspace.tabs.flatMap { tab in
                tab.agents.map { agent in
                    HerdrAgent(
                        paneId: agent.id,
                        workspaceId: workspace.id,
                        kind: agent.kind,
                        status: agent.status,
                        sessionId: agent.sessionId,
                        terminalTitle: agent.title
                    )
                }
            } + herdrAgents(in: workspace.children)
        }
    }

    static let defaultTree = [
        workspace("w1", tabs: [
            TabNode(id: "w1:t1", title: "Claude", agents: [agent("w1:p1", sessionId: sessionA, title: "terminal-title", branch: "feature/foreground")]),
            TabNode(id: "w1:t2", title: "Codex", agents: [agent("w1:p2", kind: "codex", title: "codex")]),
            TabNode(id: "w1:t3", title: "shell"),
        ]),
    ]

    static func item(_ id: String, text: String) -> ChatItem {
        ChatItem(id: id, at: start, kind: .assistantText(markdown: text))
    }

    static func page(_ items: [ChatItem], meta: TranscriptMeta = TranscriptMeta(), before: String? = nil) -> TranscriptPage {
        TranscriptPage(items: items, before: before, hasMore: before != nil, meta: meta)
    }
}

struct HubHarness {
    let herdr: FakeHerdrBridge
    let transcripts: FakeTranscriptProvider
    let clock: ManualClock
    let devices: DeviceStore
    let pairing: Pairing
    let hub: SessionHub
    let directory: URL

    func connect() -> TestClientSocket {
        let socket = TestClientSocket()
        let hub = hub
        Task {
            await hub.serve(socket, messages: socket.incoming)
        }
        return socket
    }

    func pairedClient(name: String = "iPhone de Teste") async throws -> (socket: TestClientSocket, helloOk: HelloOkPayload) {
        let code = await pairing.issueCode(url: Sample.pairingURL)
        let socket = connect()
        let reply = try await socket.reply(
            to: .hello(HelloPayload(pairingCode: code.code, deviceName: name, appVersion: "1.0")),
            id: "hello-1"
        )
        guard case .helloOk(let helloOk) = reply else { throw UnexpectedMessage(message: reply) }
        let tree = try await socket.next()
        #expect(tree.id == "hello-1")
        guard case .tree = tree.message else { throw UnexpectedMessage(message: tree.message) }
        return (socket, helloOk)
    }

    func client(token: String) async throws -> TestClientSocket {
        let socket = connect()
        let reply = try await socket.reply(to: .hello(HelloPayload(deviceToken: token, deviceName: "iPhone", appVersion: "1.0")), id: "hello-1")
        guard case .helloOk = reply else { throw UnexpectedMessage(message: reply) }
        _ = try await socket.next()
        return socket
    }

    func advanceTreeDebounce(expectingSleepers count: Int = 1) async throws {
        try await clock.waitForSleepers(count)
        clock.advance(by: .milliseconds(150))
    }
}

func withHub(
    tree: [WorkspaceNode] = Sample.defaultTree,
    agents: [HerdrAgent]? = nil,
    available: Bool = true,
    configure: (FakeTranscriptProvider) async -> Void = { _ in },
    _ body: (HubHarness) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-hub-\(UUID().uuidString)", directoryHint: .isDirectory)
    let herdr = FakeHerdrBridge(tree: tree, agents: agents ?? Sample.herdrAgents(in: tree), available: available)
    let transcripts = FakeTranscriptProvider()
    await configure(transcripts)
    let clock = ManualClock(origin: Sample.start)
    let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
    let pairing = Pairing(clock: clock)
    let hub = SessionHub(
        herdr: herdr,
        transcripts: transcripts,
        devices: devices,
        pairing: pairing,
        clock: clock,
        configuration: SessionHubConfiguration(hostName: "Mac de Teste", daemonVersion: "9.9.9")
    )
    await hub.start()
    let harness = HubHarness(
        herdr: herdr,
        transcripts: transcripts,
        clock: clock,
        devices: devices,
        pairing: pairing,
        hub: hub,
        directory: directory
    )
    do {
        try await body(harness)
    } catch {
        await hub.shutdown()
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    await hub.shutdown()
    try? FileManager.default.removeItem(at: directory)
}
