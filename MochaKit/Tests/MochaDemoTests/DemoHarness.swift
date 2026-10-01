import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

struct Timeout: Error, CustomStringConvertible {
    let description: String
}

struct UnexpectedMessage: Error, CustomStringConvertible {
    let envelope: ServerEnvelope
    var description: String { "Mensagem inesperada: \(envelope)" }
}

actor Recorder<Element: Sendable> {
    private var elements: [Element] = []
    private var cursor = 0

    func record(_ element: Element) {
        elements.append(element)
    }

    func next(
        within timeout: Duration = .seconds(5),
        where predicate: @Sendable (Element) -> Bool = { _ in true }
    ) async throws -> Element {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            while cursor < elements.count {
                let element = elements[cursor]
                cursor += 1
                if predicate(element) {
                    return element
                }
            }
            guard ContinuousClock.now < deadline else {
                throw Timeout(description: "Nada chegou em \(timeout)")
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    func unread() -> [Element] {
        Array(elements[cursor...])
    }

    func all() -> [Element] {
        elements
    }
}

extension DemoOptions {
    static let fast = DemoOptions(
        connectDelay: .milliseconds(5),
        echoDelay: .milliseconds(5),
        replyDelay: .milliseconds(5),
        newAgentTabDelay: .milliseconds(5)
    )

    static let scriptScale = 0.05

    static let script = DemoOptions(
        runsScript: true,
        connectDelay: .milliseconds(5),
        echoDelay: .milliseconds(5),
        replyDelay: .milliseconds(5),
        scriptTimeScale: scriptScale
    )
}

extension ServerMessage {
    var workspaces: [WorkspaceNode]? {
        switch self {
        case .tree(let workspaces), .treeChanged(let workspaces): workspaces
        default: nil
        }
    }

    var changedWorkspaces: [WorkspaceNode]? {
        guard case .treeChanged(let workspaces) = self else { return nil }
        return workspaces
    }

    var archivedSessions: [ArchivedSession]? {
        guard case .archived(let sessions) = self else { return nil }
        return sessions
    }

    var herdrConnected: Bool? {
        guard case .herdrStatus(let connected) = self else { return nil }
        return connected
    }
}

extension ChatItem {
    var toolCall: ToolCall? {
        guard case .toolCall(let toolCall) = kind else { return nil }
        return toolCall
    }
}

final class DemoHarness: Sendable {
    let launch: Date
    let dataset: DemoDataset
    let connection: DemoServerConnection
    let messages: Recorder<ServerEnvelope>
    let states: Recorder<ConnectionState>
    private let consumers: [Task<Void, Never>]

    init(_ options: DemoOptions = .fast, launch: Date = Date(), adjusting adjust: (inout DemoDataset) -> Void = { _ in }) throws {
        var dataset = try DemoDataset.bundled(now: launch, isEmpty: options.isEmpty)
        adjust(&dataset)
        let connection = DemoServerConnection(dataset: dataset, options: options)
        let messages = Recorder<ServerEnvelope>()
        let states = Recorder<ConnectionState>()
        let messageStream = connection.messages
        let stateStream = connection.states
        consumers = [
            Task {
                for await message in messageStream {
                    await messages.record(message)
                }
            },
            Task {
                for await state in stateStream {
                    await states.record(state)
                }
            },
        ]
        self.launch = launch
        self.dataset = dataset
        self.connection = connection
        self.messages = messages
        self.states = states
    }

    deinit {
        for consumer in consumers {
            consumer.cancel()
        }
    }

    func connect() async throws {
        #expect(try await states.next() == .idle)
        await connection.start()
        #expect(try await states.next() == .connecting)
        #expect(try await states.next() == .connected)
        let helloOk = try await messages.next()
        guard case .helloOk = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        let tree = try await messages.next()
        guard case .tree = tree.message else { throw UnexpectedMessage(envelope: tree) }
        let archived = try await messages.next()
        guard case .archived = archived.message else { throw UnexpectedMessage(envelope: archived) }
        let usage = try await messages.next()
        guard case .usage = usage.message else { throw UnexpectedMessage(envelope: usage) }
        if dataset.codexUsage != nil {
            let codexUsage = try await messages.next()
            guard case .usage(let snapshot) = codexUsage.message, snapshot.provider == .codex else { throw UnexpectedMessage(envelope: codexUsage) }
        }
    }

    func request(_ message: ClientMessage) async throws -> ServerEnvelope {
        let id = "c-" + UUID().uuidString
        try await connection.send(message, id: id)
        return try await messages.next { $0.id == id }
    }

    func page(_ agentId: AgentID, before: String? = nil, limit: Int? = nil) async throws -> ChatPage {
        try await page(.agent(agentId), before: before, limit: limit)
    }

    func page(_ target: ChatTarget, before: String? = nil, limit: Int? = nil) async throws -> ChatPage {
        let envelope = try await request(.openChat(target: target, before: before, limit: limit))
        guard case .chatPage(let page) = envelope.message else { throw UnexpectedMessage(envelope: envelope) }
        return page
    }

    func error(for message: ClientMessage) async throws -> (code: ProtocolErrorCode, message: String) {
        let envelope = try await request(message)
        guard case .error(let code, let text) = envelope.message else { throw UnexpectedMessage(envelope: envelope) }
        return (code, text)
    }
}
