import Foundation
import MochaClient
import MochaProtocol
import Observation
import SwiftUI

struct ChatState: Equatable {
    let route: ChatTarget
    var target: ChatTarget
    var sessionId: String?
    var meta: ChatMeta?
    var items: [ChatItem] = []
    var before: String?
    var hasMore = false
    var isLoading = true
    var isLoadingOlder = false
    var failure: AppSessionError?

    var isReadOnly: Bool {
        if case .session = target { true } else { false }
    }
}

enum AppSheet: Identifiable, Hashable {
    case detail(ChatTarget)
    case usage
    case settings

    var id: Self { self }
}

enum AppSessionError: Error, Equatable {
    case notConnected
    case readOnlyChat
    case server(code: ProtocolErrorCode, message: String)
    case unexpectedReply(type: String)

    var message: String {
        switch self {
        case .notConnected: "Sem conexão com o Mac"
        case .readOnlyChat: "Sessão encerrada · só leitura"
        case .server(_, let message): message
        case .unexpectedReply(let type): "Resposta inesperada do Mac: \(type)."
        }
    }
}

@MainActor
@Observable
final class AppSession {
    static let pageSize = 60

    private(set) var connectionState: ConnectionState = .idle
    private(set) var host: HostInfo?
    private(set) var deviceId: DeviceID?
    private(set) var preferences: DevicePreferences?
    private(set) var workspaces: [WorkspaceNode] = []
    private(set) var archivedSessions: [ArchivedSession] = []
    private(set) var usage: UsageSnapshot?
    private(set) var herdrConnected: Bool?
    private(set) var hasReceivedTree = false
    private(set) var chat: ChatState?
    private(set) var chatPath: [ChatTarget] = []
    private(set) var isDrawerOpen = false
    private(set) var pairing = PairingGate()
    private(set) var pairedAt: Date?
    var sheet: AppSheet?

    @ObservationIgnored private let connection: any ServerConnection
    @ObservationIgnored private var replyContinuations: [String: CheckedContinuation<ServerMessage, any Error>] = [:]
    @ObservationIgnored private var nextRequestNumber = 0
    @ObservationIgnored private var consumerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var chatGeneration = 0
    @ObservationIgnored private let pairingDates: any PairingDateStore
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var isSceneActive = false

    init(connection: any ServerConnection, pairingDates: any PairingDateStore = InMemoryPairingDateStore()) {
        self.connection = connection
        self.pairingDates = pairingDates
        pairedAt = pairingDates.pairedAt
    }

    var showsPairing: Bool {
        pairing.showsPairing
    }

    var foregroundAgentId: AgentID? {
        guard case .agent(let agentId)? = visibleChat?.target else { return nil }
        return agentId
    }

    var visibleChat: ChatState? {
        guard let route = chatPath.last, let chat, chat.route == route else { return nil }
        return chat
    }

    var claudeAgents: [AgentSummary] {
        workspaces.allAgents.filter { $0.kind == AgentKind.claude }
    }

    func chat(for route: ChatTarget) -> ChatState? {
        guard let chat, chat.route == route else { return nil }
        return chat
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
        enqueueLifecycle { await $0.start() }
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        isSceneActive = phase == .active
        sendForeground()
        guard hasStarted else { return }
        switch phase {
        case .active:
            enqueueLifecycle { await $0.start() }
        case .background:
            enqueueLifecycle { await $0.stop() }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func sendForeground() {
        guard connectionState == .connected else { return }
        nextRequestNumber += 1
        let id = "c-\(nextRequestNumber)"
        let message = ClientMessage.setForeground(agentId: foregroundAgentId, isActive: isSceneActive)
        enqueueLifecycle { try? await $0.send(message, id: id) }
    }

    func handle(_ url: URL) {
        switch DeepLink(url) {
        case .agent(let agentId):
            openChat(.agent(agentId))
        case .pair(let link):
            pair(link)
        case nil:
            break
        }
    }

    func pair(_ link: PairingLink) {
        if pairing.begin(link) {
            coverWithPairing()
        }
        enqueueLifecycle { await $0.pair(link) }
    }

    func unpair() async throws {
        do {
            try await request(.unpair)
        } catch AppSessionError.notConnected where connectionState == .pairingRequired(nil) {
        }
        pairedAt = nil
        pairingDates.pairedAt = nil
    }

    func openChat(_ target: ChatTarget) {
        isDrawerOpen = false
        sheet = nil
        if let current = visibleChat, current.route == target || current.target == target {
            if current.failure != nil {
                loadLatestPage()
            }
            return
        }
        if let previous = visibleChat?.target {
            sendWithoutReply(.closeChat(target: previous))
        }
        chat = ChatState(route: target, target: target, sessionId: sessionId(for: target))
        chatPath = [target]
        loadLatestPage()
    }

    func closeChat() {
        guard !chatPath.isEmpty else { return }
        chatPath = []
        leaveChat()
    }

    func setChatPath(_ path: [ChatTarget]) {
        guard path != chatPath else { return }
        if path.isEmpty {
            closeChat()
        } else if let target = path.last {
            openChat(target)
        }
    }

    func openDrawer() {
        isDrawerOpen = true
    }

    func closeDrawer() {
        isDrawerOpen = false
    }

    func showDetail(_ target: ChatTarget) {
        isDrawerOpen = false
        sheet = .detail(target)
    }

    func showUsage() {
        isDrawerOpen = false
        sheet = .usage
    }

    func showSettings() {
        isDrawerOpen = false
        sheet = .settings
    }

    func dismissSheet() {
        sheet = nil
    }

    func archive(sessionId: String) async throws {
        try await request(.archive(sessionId: sessionId))
    }

    func sendPrompt(_ text: String) async throws {
        try await request(.sendPrompt(agentId: try visibleAgentId(), text: text))
    }

    func interrupt() async throws {
        try await request(.interrupt(agentId: try visibleAgentId()))
    }

    func loadOlderItems() {
        guard
            let current = visibleChat,
            current.hasMore,
            let before = current.before,
            !current.isLoading,
            !current.isLoadingOlder
        else { return }
        chat?.isLoadingOlder = true
        let generation = chatGeneration
        Task {
            do {
                let reply = try await request(.openChat(target: current.target, before: before, limit: Self.pageSize))
                guard generation == chatGeneration else { return }
                guard case .chatPage(let page) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                prependOlder(page)
            } catch {
                guard generation == chatGeneration else { return }
                chat?.isLoadingOlder = false
                chat?.failure = Self.sessionError(from: error)
            }
        }
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

    private func visibleAgentId() throws -> AgentID {
        guard let target = visibleChat?.target else { throw AppSessionError.notConnected }
        guard case .agent(let agentId) = target else { throw AppSessionError.readOnlyChat }
        return agentId
    }

    private func sendWithoutReply(_ message: ClientMessage) {
        Task { try? await request(message) }
    }

    private func leaveChat() {
        chatGeneration += 1
        guard let target = chat?.target else { return }
        sendWithoutReply(.closeChat(target: target))
    }

    private func sessionId(for target: ChatTarget) -> String? {
        switch target {
        case .agent(let agentId): workspaces.agent(withId: agentId)?.sessionId
        case .session(let sessionId): sessionId
        }
    }

    private func apply(_ state: ConnectionState) {
        let wasConnected = connectionState == .connected
        connectionState = state
        if pairing.apply(state) {
            coverWithPairing()
        }
        guard state == .connected else {
            failAllReplies(with: .notConnected)
            return
        }
        if !wasConnected {
            reopenVisibleChat()
            sendForeground()
        }
    }

    private func coverWithPairing() {
        sheet = nil
        isDrawerOpen = false
    }

    private func recordPairing() {
        let now = Date()
        pairedAt = now
        pairingDates.pairedAt = now
    }

    private func enqueueLifecycle(_ operation: @escaping @Sendable (any ServerConnection) async -> Void) {
        let previous = lifecycleTask
        let connection = connection
        lifecycleTask = Task {
            await previous?.value
            await operation(connection)
        }
    }

    private func receive(_ envelope: ServerEnvelope) {
        if let id = envelope.id, let continuation = replyContinuations.removeValue(forKey: id) {
            continuation.resume(returning: envelope.message)
            return
        }
        switch envelope.message {
        case .helloOk(let payload):
            if payload.deviceToken != nil {
                recordPairing()
            }
            host = payload.host
            deviceId = payload.deviceId
            preferences = payload.preferences
            herdrConnected = payload.host.herdrConnected
        case .tree(let newWorkspaces), .treeChanged(let newWorkspaces):
            applyTree(newWorkspaces)
        case .archived(let sessions):
            archivedSessions = sessions
        case .usage(let snapshot):
            usage = snapshot
        case .herdrStatus(let connected):
            herdrConnected = connected
            host?.herdrConnected = connected
        case .agentStatus(let agentId, let status, let title):
            applyAgentStatus(agentId: agentId, status: status, title: title)
        case .chatAppend(let target, let items):
            appendToChat(target: target, items: items)
        case .chatUpdate(let target, let items):
            updateChat(target: target, items: items)
        case .chatMeta(let target, let meta):
            guard chat?.target == target else { return }
            chat?.meta = meta
        case .chatPage, .pending, .ack, .pong, .error, .unknown:
            break
        }
    }

    private func applyTree(_ newWorkspaces: [WorkspaceNode]) {
        workspaces = newWorkspaces
        hasReceivedTree = true
        guard let current = visibleChat else { return }
        switch ChatTargetTracking.change(for: current.target, knownSessionId: current.sessionId, in: newWorkspaces) {
        case .unchanged:
            break
        case .learnedSession(let sessionId):
            chat?.sessionId = sessionId
        case .sessionSwitched(let sessionId):
            chat?.sessionId = sessionId
            loadLatestPage()
        case .agentMoved(let agentId):
            chat?.target = .agent(agentId)
        }
    }

    private func applyAgentStatus(agentId: AgentID, status: AgentStatus, title: String?) {
        workspaces.updateAgent(withId: agentId) { agent in
            agent.status = status
            if let title {
                agent.title = title
            }
        }
        guard chat?.target == .agent(agentId) else { return }
        chat?.meta?.status = status
        if let title {
            chat?.meta?.title = title
        }
    }

    private func appendToChat(target: ChatTarget, items: [ChatItem]) {
        guard let current = chat, current.target == target else { return }
        let knownIds = Set(current.items.map(\.id))
        chat?.items.append(contentsOf: items.filter { !knownIds.contains($0.id) })
    }

    private func updateChat(target: ChatTarget, items: [ChatItem]) {
        guard let current = chat, current.target == target else { return }
        var updated = current.items
        for item in items {
            guard let index = updated.firstIndex(where: { $0.id == item.id }) else { continue }
            updated[index] = item
        }
        chat?.items = updated
    }

    private func reopenVisibleChat() {
        guard visibleChat != nil else { return }
        loadLatestPage()
    }

    private func loadLatestPage() {
        guard let current = visibleChat else { return }
        chatGeneration += 1
        let generation = chatGeneration
        chat?.isLoading = true
        chat?.failure = nil
        Task {
            do {
                let reply = try await request(.openChat(target: current.target, limit: Self.pageSize))
                guard generation == chatGeneration else { return }
                guard case .chatPage(let page) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                replaceChat(with: page)
            } catch {
                guard generation == chatGeneration else { return }
                chat?.isLoading = false
                chat?.failure = Self.sessionError(from: error)
            }
        }
    }

    private func replaceChat(with page: ChatPage) {
        guard let current = chat else { return }
        chat = ChatState(
            route: current.route,
            target: page.target,
            sessionId: sessionId(for: page.target) ?? current.sessionId,
            meta: page.meta,
            items: page.items,
            before: page.before,
            hasMore: page.hasMore,
            isLoading: false
        )
    }

    private func prependOlder(_ page: ChatPage) {
        guard let current = chat, current.target == page.target else { return }
        let knownIds = Set(current.items.map(\.id))
        chat?.items.insert(contentsOf: page.items.filter { !knownIds.contains($0.id) }, at: 0)
        chat?.before = page.before
        chat?.hasMore = page.hasMore
        chat?.meta = page.meta
        chat?.isLoadingOlder = false
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

enum AgentKind {
    static let claude = "claude"
}
