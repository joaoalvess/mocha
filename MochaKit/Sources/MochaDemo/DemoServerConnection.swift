import Foundation
import MochaProtocol

public actor DemoServerConnection: ServerConnection {
    public nonisolated let messages: AsyncStream<ServerEnvelope>

    static let defaultPageSize = 60
    static let maximumPageSize = 200
    static let cursorPrefix = "demo:"
    static let host = HostInfo(hostName: "Mac de demonstração", daemonVersion: "0.1.0-demo", herdrConnected: true)
    static let deviceId: DeviceID = "D3E0D3E0-0000-4000-8000-000000000001"
    static let deviceToken = "demo-device-token"
    static let replyMarkdown = """
    Isto é o **modo demo** do Mocha: nenhuma mensagem saiu do iPhone.

    No uso real, o prompt vai para o Claude Code no Mac pelo `mochad`, e a resposta aparece aqui assim que o Claude a grava no transcript.
    """

    private let continuation: AsyncStream<ServerEnvelope>.Continuation
    private let replyDelay: Duration
    private let workspaces: [WorkspaceNode]
    private var items: [AgentID: [ChatItem]]
    private var metas: [AgentID: ChatMeta]
    private var openChats: Set<AgentID> = []
    private var preferences = DevicePreferences()
    private var turns: [AgentID: Task<Void, Never>] = [:]
    private var nextRequestNumber = 1
    private var isClosed = false

    public init(replyDelay: Duration = .seconds(2)) throws {
        self.init(dataset: try DemoDataset.bundled(), replyDelay: replyDelay)
    }

    init(dataset: DemoDataset, replyDelay: Duration) {
        let (stream, continuation) = AsyncStream.makeStream(of: ServerEnvelope.self)
        self.messages = stream
        self.continuation = continuation
        self.replyDelay = replyDelay
        self.workspaces = dataset.workspaces
        self.items = Dictionary(dataset.chats.map { ($0.agentId, $0.items) }, uniquingKeysWith: { first, _ in first })
        self.metas = Dictionary(dataset.chats.map { ($0.agentId, $0.meta) }, uniquingKeysWith: { first, _ in first })
    }

    deinit {
        continuation.finish()
        for turn in turns.values {
            turn.cancel()
        }
    }

    public func send(_ message: ClientMessage) async throws -> String {
        guard !isClosed else { throw DemoError.connectionClosed }
        let id = "c-\(nextRequestNumber)"
        nextRequestNumber += 1
        handle(message, id: id)
        return id
    }

    private func handle(_ message: ClientMessage, id: String) {
        switch message {
        case .hello(let hello):
            let token = hello.pairingCode == nil ? nil : Self.deviceToken
            reply(id, .helloOk(HelloOkPayload(host: Self.host, deviceId: Self.deviceId, deviceToken: token, preferences: preferences)))
            reply(id, .tree(workspaces: workspaces))
        case .openChat(let agentId, let before, let limit):
            openChat(agentId: agentId, before: before, limit: limit, id: id)
        case .closeChat(let agentId):
            openChats.remove(agentId)
            reply(id, .ack())
        case .sendPrompt(let agentId, let text):
            sendPrompt(agentId: agentId, text: text, id: id)
        case .interrupt(let agentId):
            interrupt(agentId: agentId, id: id)
        case .setForeground, .registerLiveActivity:
            reply(id, .ack())
        case .unpair:
            reply(id, .ack())
            close()
        case .ping:
            reply(id, .pong)
        case .slash(let agentId, _):
            guard metas[agentId] != nil else { return fail(id, .agentNotFound, "Agente não encontrado.") }
            reply(id, .ack())
        case .setPreferences(let newPreferences):
            preferences = newPreferences
            reply(id, .ack())
        case .respond:
            fail(id, .requestNotFound, "Pedido não encontrado.")
        case .newAgentTab:
            fail(id, .internal, "Nova tab não está disponível no modo demo.")
        case .unknown(let type):
            fail(id, .unknownType, "Tipo de mensagem desconhecido: \(type).")
        }
    }

    private func openChat(agentId: AgentID, before: String?, limit: Int?, id: String) {
        guard let chatItems = items[agentId], let meta = metas[agentId] else {
            return fail(id, .agentNotFound, "Agente não encontrado.")
        }
        var end = chatItems.count
        if let before {
            guard let index = Self.index(fromCursor: before), (0...chatItems.count).contains(index) else {
                return fail(id, .invalidPayload, "Cursor de paginação inválido.")
            }
            end = index
        }
        let pageSize = min(max(limit ?? Self.defaultPageSize, 1), Self.maximumPageSize)
        let start = max(0, end - pageSize)
        let hasMore = start > 0
        openChats.insert(agentId)
        let page = ChatPage(
            agentId: agentId,
            meta: meta,
            items: Array(chatItems[start..<end]),
            before: hasMore ? Self.cursor(forIndex: start) : nil,
            hasMore: hasMore
        )
        reply(id, .chatPage(page))
    }

    private func sendPrompt(agentId: AgentID, text: String, id: String) {
        guard let meta = metas[agentId] else {
            return fail(id, .agentNotFound, "Agente não encontrado.")
        }
        guard meta.status != .blocked else {
            return fail(id, .agentBlocked, "O agente está esperando uma resposta no terminal.")
        }
        reply(id, .ack())
        let startedAt = Date()
        append([ChatItem(id: Self.newItemId(), at: startedAt, kind: .userPrompt(text: text, imageCount: 0))], to: agentId)
        setStatus(.working, for: agentId)
        turns[agentId]?.cancel()
        turns[agentId] = Task { [weak self, replyDelay] in
            do {
                try await Task.sleep(for: replyDelay)
            } catch {
                return
            }
            await self?.finishTurn(agentId: agentId, startedAt: startedAt)
        }
    }

    private func finishTurn(agentId: AgentID, startedAt: Date) {
        guard !Task.isCancelled else { return }
        turns[agentId] = nil
        let now = Date()
        let durationMs = Int((now.timeIntervalSince(startedAt) * 1000).rounded())
        append(
            [
                ChatItem(id: Self.newItemId(), at: now, kind: .assistantText(markdown: Self.replyMarkdown)),
                ChatItem(id: Self.newItemId(), at: now, kind: .turnFooter(durationMs: durationMs)),
            ],
            to: agentId
        )
        setStatus(.idle, for: agentId)
    }

    private func interrupt(agentId: AgentID, id: String) {
        guard metas[agentId] != nil else {
            return fail(id, .agentNotFound, "Agente não encontrado.")
        }
        reply(id, .ack())
        guard let turn = turns.removeValue(forKey: agentId) else { return }
        turn.cancel()
        setStatus(.idle, for: agentId)
    }

    private func append(_ newItems: [ChatItem], to agentId: AgentID) {
        items[agentId, default: []].append(contentsOf: newItems)
        guard openChats.contains(agentId) else { return }
        emit(.chatAppend(agentId: agentId, items: newItems))
    }

    private func setStatus(_ status: AgentStatus, for agentId: AgentID) {
        metas[agentId]?.status = status
        emit(.agentStatus(agentId: agentId, status: status))
    }

    private func close() {
        isClosed = true
        for turn in turns.values {
            turn.cancel()
        }
        turns = [:]
        continuation.finish()
    }

    private func reply(_ id: String, _ message: ServerMessage) {
        continuation.yield(ServerEnvelope(id: id, message: message))
    }

    private func emit(_ message: ServerMessage) {
        continuation.yield(ServerEnvelope(message: message))
    }

    private func fail(_ id: String, _ code: ProtocolErrorCode, _ message: String) {
        reply(id, .error(code: code, message: message))
    }

    static func cursor(forIndex index: Int) -> String {
        cursorPrefix + String(index)
    }

    static func index(fromCursor cursor: String) -> Int? {
        guard cursor.hasPrefix(cursorPrefix) else { return nil }
        return Int(cursor.dropFirst(cursorPrefix.count))
    }

    private static func newItemId() -> String {
        "demo-" + UUID().uuidString.lowercased()
    }
}
