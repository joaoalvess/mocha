import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

enum PendingSample {
    static let agent: AgentID = "w1:p1"
    static let secret = "test-secret"
    static let bashSession = "22222222-2222-4222-8222-222222222222"
    static let questionSession = "33333333-3333-4333-8333-333333333333"

    static func fixture(_ file: String) throws -> Data {
        try Fixtures.data("hooks/\(file)")
    }

    static func json(_ file: String) throws -> OrderedJSON {
        try OrderedJSON.parse(fixture(file))
    }

    static func body(_ file: String, session: String? = nil) throws -> Data {
        guard let session else { return try fixture(file) }
        return Data(try json(file).setting("session_id", to: .string(session)).compactSerialized().utf8)
    }

    static func hookRequest(_ name: HookEventName, body: Data, pane: String = agent) -> HttpRequest {
        HttpRequest(
            method: .post,
            path: name.path,
            headers: ["Content-Type": "application/json", HookServer.secretHeader: secret, HookServer.paneHeader: pane],
            body: body
        )
    }

    static func permissionHook(_ file: String, agent: AgentID = agent, session: String? = nil, at date: Date = Sample.start) throws -> (hook: ReceivedHook, request: PermissionRequestHook) {
        let event = try HookEvent.decode(.permissionRequest, from: body(file, session: session))
        guard case .permissionRequest(let request) = event else { throw PendingTestError.notAPermissionRequest }
        return (ReceivedHook(agentId: agent, receivedAt: date, event: event), request)
    }

    static func sessionHook(_ name: HookEventName, _ file: String, session: String, agent: AgentID = agent) throws -> ReceivedHook {
        ReceivedHook(agentId: agent, receivedAt: Sample.start, event: try HookEvent.decode(name, from: body(file, session: session)))
    }

    static func toolCall(_ id: String, name: String, status: ToolStatus) -> ChatItem {
        ChatItem(
            id: "item-\(id)",
            at: Sample.start,
            kind: .toolCall(ToolCall(toolUseId: id, name: name, summary: "", inputJSON: "{}", status: status))
        )
    }

    static func withoutTrailingNewline(_ data: Data) -> Data {
        data.last == UInt8(ascii: "\n") ? data.dropLast() : data
    }
}

enum PendingTestError: Error {
    case notAPermissionRequest
    case invalidSequenceLine(String)
}

struct HookSequenceLine: Sendable {
    let dt: Double
    let json: OrderedJSON

    var source: String { json["source"]?.stringValue ?? "" }
    var event: String? { json["event"]?.stringValue }
    var action: String? { json["action"]?.stringValue }
    var requestId: String? { json["requestId"]?.stringValue }
    var body: OrderedJSON? { json["body"] }

    static func load(_ name: String) throws -> [HookSequenceLine] {
        let text = String(decoding: try PendingSample.fixture(name), as: UTF8.self)
        return try text.split(whereSeparator: \.isNewline).map { line in
            let json = try OrderedJSON.parse(Data(line.utf8))
            guard case .number(let lexeme) = json["dt"], let dt = Double(lexeme) else {
                throw PendingTestError.invalidSequenceLine(String(line))
            }
            return HookSequenceLine(dt: dt, json: json)
        }
    }
}

final class HeldHook: Sendable {
    let requestId: RequestID
    private let task: Task<HttpResponse, Never>

    init(requestId: RequestID, task: Task<HttpResponse, Never>) {
        self.requestId = requestId
        self.task = task
    }

    func response() async -> HttpResponse {
        await task.value
    }

    func closeConnection() {
        task.cancel()
    }
}

struct SequenceReplay {
    let held: HeldHook
    var phoneBody: OrderedJSON?
    var lateRespondErrors: [PendingRespondError] = []
}

struct PendingHarness {
    let herdr: FakeHerdrBridge
    let transcripts: FakeTranscriptProvider
    let clock: ManualClock
    let store: PendingStore
    let hooks: HookEventHub
    let server: HookServer

    func hold(_ file: String, session: String? = nil, pane: String = PendingSample.agent, watchingTranscript: Bool = true) async throws -> HeldHook {
        let known = Set(await store.requests.map(\.id))
        let request = PendingSample.hookRequest(.permissionRequest, body: try PendingSample.body(file, session: session), pane: pane)
        let server = server
        let task = Task { await server.respond(to: request, as: .permissionRequest) }
        let requestId = try await eventually { await store.requests.map(\.id).first { !known.contains($0) } }
        try await clock.waitForSleepers(await store.requests.count)
        if watchingTranscript {
            _ = try await eventually { await store.isWatchingTranscript(requestId) ? true : nil }
        }
        return HeldHook(requestId: requestId, task: task)
    }

    @discardableResult
    func post(_ name: HookEventName, _ file: String, session: String, pane: String = PendingSample.agent) async throws -> HttpResponse {
        await server.respond(to: PendingSample.hookRequest(name, body: try PendingSample.body(file, session: session), pane: pane), as: name)
    }

    func emitStatus(_ status: AgentStatus, agent: AgentID = PendingSample.agent) async throws {
        try await observing { herdr.emit(.agentStatus(agent, status, title: nil)) }
    }

    func emitTranscript(_ delta: TranscriptDelta, session: String, watched: Bool) async throws {
        guard watched else {
            await transcripts.emit(delta, toSession: session)
            return
        }
        let before = await store.observedEvents
        await transcripts.emit(delta, toSession: session)
        _ = try await eventually { await store.observedEvents > before ? true : nil }
    }

    func observing(_ action: () -> Void) async throws {
        let before = await store.observedEvents
        action()
        _ = try await eventually { await store.observedEvents > before ? true : nil }
    }

    func resolution(of requestId: RequestID) async throws -> PendingResolution {
        try await eventually { await store.recentResolutions.last { $0.requestId == requestId } }
    }

    func closeAndWait(_ held: HeldHook) async throws {
        held.closeConnection()
        _ = try await eventually { await store.contains(held.requestId) ? nil : true }
    }

    func replay(_ sequence: String, fixture: String, session: String, skipping skip: (HookSequenceLine) -> Bool = { _ in false }) async throws -> SequenceReplay {
        var replay: SequenceReplay?
        var labRequestId: String?
        var toolNames: [String: String] = [:]
        var elapsed = 0.0
        for line in try HookSequenceLine.load(sequence) where !skip(line) {
            let step = Int64(((line.dt - elapsed) * 1000).rounded())
            if step > 0 {
                clock.advance(by: .milliseconds(step))
                elapsed = line.dt
            }
            let active: Bool
            if let held = replay?.held {
                active = await store.contains(held.requestId)
            } else {
                active = false
            }
            switch line.source {
            case "hook":
                switch line.event {
                case "PermissionRequest":
                    labRequestId = line.requestId
                    replay = SequenceReplay(held: try await hold(fixture, session: session))
                case "UserPromptSubmit":
                    try await post(.userPromptSubmit, "UserPromptSubmit.json", session: session)
                case "Stop":
                    try await post(.stop, "Stop.json", session: session)
                case "Notification":
                    try await post(.notification, "Notification.permission_prompt.json", session: session)
                default:
                    break
                }
            case "daemon":
                guard var current = replay, line.action == "respond", line.requestId == labRequestId, let body = line.body else { break }
                let response = try Self.phoneResponse(for: body)
                do {
                    try await store.respond(to: current.held.requestId, with: response)
                    current.phoneBody = body
                } catch {
                    current.lateRespondErrors.append(error)
                }
                replay = current
            case "claude":
                guard let held = replay?.held, line.action == "connectionClosed", line.requestId == labRequestId else { break }
                if active {
                    try await closeAndWait(held)
                } else {
                    held.closeConnection()
                }
            case "herdr":
                guard let status = line.json["status"]?.stringValue.flatMap(AgentStatus.init(rawValue:)) else { break }
                try await emitStatus(status)
            case "transcript":
                switch line.json["block"]?.stringValue {
                case "tool_use":
                    guard let id = line.json["id"]?.stringValue, let name = line.json["name"]?.stringValue else { break }
                    toolNames[id] = name
                    try await emitTranscript(.append([PendingSample.toolCall(id, name: name, status: .running)]), session: session, watched: active)
                case "tool_result":
                    guard let id = line.json["tool_use_id"]?.stringValue, let name = toolNames[id] else { break }
                    let status: ToolStatus = line.json["is_error"]?.boolValue == true ? .failed : .succeeded
                    try await emitTranscript(.update([PendingSample.toolCall(id, name: name, status: status)]), session: session, watched: active)
                default:
                    break
                }
            default:
                break
            }
        }
        return try #require(replay)
    }

    static func phoneResponse(for body: OrderedJSON) throws -> PendingResponse {
        let decision = try #require(body["hookSpecificOutput"]?["decision"])
        switch decision["behavior"]?.stringValue {
        case "deny":
            return .deny(reason: decision["message"]?.stringValue)
        case "allow":
            guard let answers = decision["updatedInput"]?["answers"]?.members else { return .allow }
            var chosen: [String: [String]] = [:]
            for member in answers {
                let text = try #require(member.value.stringValue)
                chosen[member.key] = text.components(separatedBy: ", ").reversed()
            }
            return .answers(chosen)
        default:
            throw PendingTestError.invalidSequenceLine(body.compactSerialized())
        }
    }
}

func withPendingStore(
    configuration: PendingStoreConfiguration = PendingStoreConfiguration(),
    configure: (FakeTranscriptProvider) async -> Void = { _ in },
    _ body: (PendingHarness) async throws -> Void
) async throws {
    let herdr = FakeHerdrBridge(tree: Sample.defaultTree, agents: Sample.herdrAgents(in: Sample.defaultTree))
    let transcripts = FakeTranscriptProvider()
    await configure(transcripts)
    let clock = ManualClock(origin: Sample.start)
    let store = PendingStore(herdr: herdr, transcripts: transcripts, clock: clock, configuration: configuration)
    await store.start()
    let hooks = HookEventHub()
    let server = HookServer(
        secrets: HookSecretVerifier(secret: PendingSample.secret),
        events: hooks,
        permissions: store,
        resolveAgent: { await herdr.resolve($0) },
        now: { clock.now() }
    )
    let harness = PendingHarness(herdr: herdr, transcripts: transcripts, clock: clock, store: store, hooks: hooks, server: server)
    _ = try await eventually { await store.observedEvents > 0 ? true : nil }
    do {
        try await body(harness)
    } catch {
        await store.shutdown()
        throw error
    }
    await store.shutdown()
}
