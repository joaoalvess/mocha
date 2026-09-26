import Foundation
import MochaProtocol
import Observation

struct VisibleChat: Equatable {
    var agentId: AgentID
    var sessionId: String?
    var meta: ChatMeta?
    var items: [ChatItem] = []
    var before: String?
    var hasMore = false
    var isLoading = true
    var isLoadingOlder = false
    var failure: AppSessionError?
}

enum AppSessionError: Error, Equatable {
    case notConnected
    case server(code: ProtocolErrorCode, message: String)
    case unexpectedReply(type: String)

    var message: String {
        switch self {
        case .notConnected: "Sem conexão com o Mac"
        case .server(_, let message): message
        case .unexpectedReply(let type): "Resposta inesperada do Mac: \(type)."
        }
    }
}

@MainActor
@Observable
final class AppSession {
    private(set) var connectionState: ConnectionState = .idle
    private(set) var host: HostInfo?
    private(set) var deviceId: DeviceID?
    private(set) var preferences: DevicePreferences?
    private(set) var workspaces: [WorkspaceNode] = []
    private(set) var hasReceivedTree = false
    private(set) var visibleChat: VisibleChat?
    private(set) var pairingLink: PairingLink?
    var isDrawerOpen = false
    var isSettingsPresented = false
    var isPairingPresented = false

    @ObservationIgnored private let connection: any ServerConnection
    @ObservationIgnored private var replyContinuations: [String: CheckedContinuation<ServerMessage, any Error>] = [:]
    @ObservationIgnored private var nextRequestNumber = 0
    @ObservationIgnored private var consumerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var chatGeneration = 0

    init(connection: any ServerConnection) {
        self.connection = connection
    }

    var needsPairing: Bool {
        if case .pairingRequired = connectionState { true } else { false }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let states = connection.states
        let messages = connection.messages
        consumerTasks = [
            Task { [weak self] in
                for await state in states {
                    self?.apply(state)
                }
            },
            Task { [weak self] in
                for await envelope in messages {
                    self?.receive(envelope)
                }
            },
        ]
        let connection = connection
        Task { await connection.start() }
    }

    func handle(_ url: URL) {
        switch DeepLink(url) {
        case .agent(let agentId):
            openChat(agentId)
        case .pair(let link):
            pair(link)
        case nil:
            break
        }
    }

    func pair(_ link: PairingLink) {
        pairingLink = link
        isPairingPresented = true
        let connection = connection
        Task { await connection.pair(link) }
    }

    func openChat(_ agentId: AgentID) {
        isDrawerOpen = false
        if let current = visibleChat, current.agentId == agentId, current.failure == nil {
            return
        }
        let previous = visibleChat?.agentId
        visibleChat = VisibleChat(agentId: agentId, sessionId: workspaces.agent(withId: agentId)?.sessionId)
        if let previous, previous != agentId {
            sendWithoutReply(.closeChat(agentId: previous))
        }
        loadLatestPage()
    }

    func loadOlderItems() {
        guard
            let chat = visibleChat,
            chat.hasMore,
            let before = chat.before,
            !chat.isLoading,
            !chat.isLoadingOlder
        else { return }
        visibleChat?.isLoadingOlder = true
        let generation = chatGeneration
        Task {
            do {
                let reply = try await request(.openChat(agentId: chat.agentId, before: before))
                guard generation == chatGeneration else { return }
                guard case .chatPage(let page) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                prependOlder(page)
            } catch {
                guard generation == chatGeneration else { return }
                visibleChat?.isLoadingOlder = false
                visibleChat?.failure = Self.sessionError(from: error)
            }
        }
    }

    func sendPrompt(_ text: String) async throws {
        guard let agentId = visibleChat?.agentId else { throw AppSessionError.notConnected }
        try await request(.sendPrompt(agentId: agentId, text: text))
    }

    func interrupt() async throws {
        guard let agentId = visibleChat?.agentId else { throw AppSessionError.notConnected }
        try await request(.interrupt(agentId: agentId))
    }

    @discardableResult
    func request(_ message: ClientMessage) async throws -> ServerMessage {
        guard connectionState == .connected else { throw AppSessionError.notConnected }
        nextRequestNumber += 1
        let id = "c-\(nextRequestNumber)"
        let connection = connection
        let reply: ServerMessage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ServerMessage, any Error>) in
            replyContinuations[id] = continuation
            Task {
                do {
                    try await connection.send(message, id: id)
                } catch {
                    self.failReply(id: id, with: .notConnected)
                }
            }
        }
        if case .error(let code, let text) = reply {
            throw AppSessionError.server(code: code, message: text)
        }
        return reply
    }

    private func sendWithoutReply(_ message: ClientMessage) {
        Task { try? await request(message) }
    }

    private func apply(_ state: ConnectionState) {
        let wasConnected = connectionState == .connected
        connectionState = state
        if state != .connected {
            failAllReplies(with: .notConnected)
        } else if !wasConnected {
            reopenVisibleChat()
        }
    }

    private func receive(_ envelope: ServerEnvelope) {
        if let id = envelope.id, let continuation = replyContinuations.removeValue(forKey: id) {
            continuation.resume(returning: envelope.message)
            return
        }
        switch envelope.message {
        case .helloOk(let payload):
            host = payload.host
            deviceId = payload.deviceId
            preferences = payload.preferences
        case .tree(let newWorkspaces), .treeChanged(let newWorkspaces):
            applyTree(newWorkspaces)
        case .agentStatus(let agentId, let status, let title):
            applyAgentStatus(agentId: agentId, status: status, title: title)
        case .chatAppend(let agentId, let items):
            appendToVisibleChat(agentId: agentId, items: items)
        case .chatUpdate(let agentId, let items):
            updateVisibleChat(agentId: agentId, items: items)
        case .chatMeta(let agentId, let meta):
            guard visibleChat?.agentId == agentId else { return }
            visibleChat?.meta = meta
        case .chatPage, .pending, .ack, .pong, .error, .unknown:
            break
        }
    }

    private func applyTree(_ newWorkspaces: [WorkspaceNode]) {
        workspaces = newWorkspaces
        hasReceivedTree = true
        guard let chat = visibleChat else { return }
        if let agent = newWorkspaces.agent(withId: chat.agentId) {
            guard let newSessionId = agent.sessionId else { return }
            guard let knownSessionId = chat.sessionId else {
                visibleChat?.sessionId = newSessionId
                return
            }
            if newSessionId != knownSessionId {
                visibleChat?.sessionId = newSessionId
                loadLatestPage()
            }
        } else if let sessionId = chat.sessionId, let moved = newWorkspaces.agent(withSessionId: sessionId) {
            visibleChat?.agentId = moved.id
        }
    }

    private func applyAgentStatus(agentId: AgentID, status: AgentStatus, title: String?) {
        workspaces.updateAgent(withId: agentId) { agent in
            agent.status = status
            if let title {
                agent.title = title
            }
        }
        guard visibleChat?.agentId == agentId else { return }
        visibleChat?.meta?.status = status
        if let title {
            visibleChat?.meta?.title = title
        }
    }

    private func appendToVisibleChat(agentId: AgentID, items: [ChatItem]) {
        guard let chat = visibleChat, chat.agentId == agentId else { return }
        let knownIds = Set(chat.items.map(\.id))
        visibleChat?.items.append(contentsOf: items.filter { !knownIds.contains($0.id) })
    }

    private func updateVisibleChat(agentId: AgentID, items: [ChatItem]) {
        guard let chat = visibleChat, chat.agentId == agentId else { return }
        var updated = chat.items
        for item in items {
            guard let index = updated.firstIndex(where: { $0.id == item.id }) else { continue }
            updated[index] = item
        }
        visibleChat?.items = updated
    }

    private func reopenVisibleChat() {
        guard visibleChat != nil else { return }
        loadLatestPage()
    }

    private func loadLatestPage() {
        guard let chat = visibleChat else { return }
        chatGeneration += 1
        let generation = chatGeneration
        visibleChat?.isLoading = true
        visibleChat?.failure = nil
        Task {
            do {
                let reply = try await request(.openChat(agentId: chat.agentId))
                guard generation == chatGeneration else { return }
                guard case .chatPage(let page) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                replaceVisibleChat(with: page)
            } catch {
                guard generation == chatGeneration else { return }
                visibleChat?.isLoading = false
                visibleChat?.failure = Self.sessionError(from: error)
            }
        }
    }

    private func replaceVisibleChat(with page: ChatPage) {
        let sessionId = workspaces.agent(withId: page.agentId)?.sessionId ?? visibleChat?.sessionId
        visibleChat = VisibleChat(
            agentId: page.agentId,
            sessionId: sessionId,
            meta: page.meta,
            items: page.items,
            before: page.before,
            hasMore: page.hasMore,
            isLoading: false
        )
    }

    private func prependOlder(_ page: ChatPage) {
        guard let chat = visibleChat, chat.agentId == page.agentId else { return }
        let knownIds = Set(chat.items.map(\.id))
        visibleChat?.items.insert(contentsOf: page.items.filter { !knownIds.contains($0.id) }, at: 0)
        visibleChat?.before = page.before
        visibleChat?.hasMore = page.hasMore
        visibleChat?.meta = page.meta
        visibleChat?.isLoadingOlder = false
    }

    private func failReply(id: String, with error: AppSessionError) {
        replyContinuations.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAllReplies(with error: AppSessionError) {
        let pending = replyContinuations
        replyContinuations = [:]
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    private static func sessionError(from error: any Error) -> AppSessionError {
        error as? AppSessionError ?? .notConnected
    }
}
