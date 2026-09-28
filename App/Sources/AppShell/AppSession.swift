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
        switch target {
        case .agent: false
        case .session, .codexThread, .subagent: true
        }
    }

    var stackEntry: ChatStackEntry {
        ChatStackEntry(route: route, target: target)
    }
}

enum AppSheet: Identifiable, Hashable {
    case detail(ChatTarget)
    case usage
    case settings
    case newSession

    var id: Self { self }
}

enum RootPage: Hashable {
    case start
    case history
}

enum AppSessionError: Error, Equatable {
    case notConnected
    case readOnlyChat
    case controlUnavailable
    case server(code: ProtocolErrorCode, message: String)
    case unexpectedReply(type: String)
    case uploadFailed(ImageUploadError)

    var message: String {
        switch self {
        case .notConnected: "Sem conexão com o Mac"
        case .readOnlyChat: "Sessão encerrada · só leitura"
        case .controlUnavailable: "Controle indisponível nesta tab Codex"
        case .server(_, let message): message
        case .unexpectedReply(let type): "Resposta inesperada do Mac: \(type)."
        case .uploadFailed: "Não foi possível enviar a imagem ao Mac"
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
    private(set) var usages: [AgentProvider: UsageSnapshot] = [:]
    private(set) var herdrConnected: Bool?
    private(set) var hasReceivedTree = false
    private(set) var chatStack: [ChatState] = []
    private var departingChats: [ChatState] = []
    private(set) var isDrawerOpen = false
    var rootPage: RootPage = .start
    private(set) var pairing = PairingGate()
    private(set) var pairedAt: Date?
    private(set) var pending = PendingInbox()
    private(set) var pendingReveal: AgentID?
    var sheet: AppSheet?
    var isInboxOpen = false

    @ObservationIgnored private let connection: any ServerConnection
    @ObservationIgnored private let uploader: any ImageUploading
    @ObservationIgnored private var replyContinuations: [String: CheckedContinuation<ServerMessage, any Error>] = [:]
    @ObservationIgnored private var nextRequestNumber = 0
    @ObservationIgnored private var consumerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var chatGenerations: [ChatTarget: Int] = [:]
    @ObservationIgnored private var nextChatGeneration = 0
    @ObservationIgnored private let pairingDates: any PairingDateStore
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var foreground = ForegroundReporter()

    init(connection: any ServerConnection, uploader: any ImageUploading, pairingDates: any PairingDateStore = InMemoryPairingDateStore()) {
        self.connection = connection
        self.uploader = uploader
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

    var chatPath: [ChatTarget] {
        chatStack.map(\.route)
    }

    var visibleChat: ChatState? {
        chatStack.last
    }

    var supportedAgents: [AgentSummary] {
        workspaces.allAgents.filter { $0.kind == AgentKind.claude || $0.kind == AgentKind.codex }
    }

    func chat(for route: ChatTarget) -> ChatState? {
        chatStack.last { $0.route == route } ?? departingChats.last { $0.route == route }
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
        AppNotifications.taps.attach { [weak self] link in
            self?.handle(link)
        }
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
        guard
            connectionState == .connected,
            let message = foreground.message(agentId: foregroundAgentId, isActive: isSceneActive)
        else { return }
        nextRequestNumber += 1
        let id = "c-\(nextRequestNumber)"
        enqueueLifecycle { try? await $0.send(message, id: id) }
    }

    func handle(_ url: URL) {
        guard let link = DeepLink(url) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .agent(let agentId):
            openChat(.agent(agentId))
        case .pair(let pairingLink):
            pair(pairingLink)
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
        isInboxOpen = false
        navigate(ChatNavigation.open(target, stack: stackEntries))
    }

    func closeChat() {
        isDrawerOpen = false
        guard !chatStack.isEmpty else { return }
        navigate(ChatNavigation.setPath([], stack: stackEntries))
    }

    func goBack() {
        navigate(ChatNavigation.back(stack: stackEntries))
    }

    func setChatPath(_ path: [ChatTarget]) {
        navigate(ChatNavigation.setPath(path, stack: stackEntries))
    }

    func subagentTarget(agentId: String?, in route: ChatTarget) -> ChatTarget? {
        guard let agentId, let sessionId = chat(for: route)?.sessionId else { return nil }
        return .subagent(sessionId: sessionId, agentId: agentId)
    }

    func openDrawer() {
        guard !chatStack.isEmpty else { return }
        isDrawerOpen = true
    }

    func showHistory() {
        rootPage = .history
    }

    func showStart() {
        rootPage = .start
    }

    func showNewSession() {
        isDrawerOpen = false
        sheet = .newSession
    }

    func closeDrawer() {
        isDrawerOpen = false
    }

    func showDetail(_ target: ChatTarget) {
        isDrawerOpen = false
        sheet = .detail(target)
    }

    var usage: UsageSnapshot? {
        usages[.claude] ?? usages[.codex]
    }

    func usage(for provider: AgentProvider) -> UsageSnapshot? {
        usages[provider]
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

    func showInbox() {
        isDrawerOpen = false
        sheet = nil
        isInboxOpen = true
    }

    func revealPendingRequest(of agentId: AgentID) {
        pendingReveal = agentId
        openChat(.agent(agentId))
    }

    func consumePendingReveal() {
        pendingReveal = nil
    }

    func respond(to requestId: RequestID, with response: PendingResponse) {
        guard pending.beginSending(requestId) else { return }
        Task {
            let outcome: PendingSendOutcome
            do {
                try await request(.respond(requestId: requestId, response: response))
                outcome = .accepted
            } catch AppSessionError.server(let code, _) where code == .requestNotFound {
                outcome = .gone
            } catch {
                outcome = .failed(Self.sessionError(from: error).message)
            }
            pending.finishSending(requestId, outcome: outcome)
        }
    }

    func setTurnDoneAlerts(_ isOn: Bool) async throws {
        let previous = preferences
        var updated = preferences ?? DevicePreferences()
        updated.turnDoneAlerts = isOn
        preferences = updated
        do {
            try await request(.setPreferences(updated))
        } catch {
            preferences = previous
            throw error
        }
    }

    func archive(sessionId: String, provider: AgentProvider = .claude) async throws {
        try await request(.archive(sessionId: sessionId, provider: provider))
    }

    func sendPrompt(_ text: String) async throws {
        try await request(.sendPrompt(agentId: try visibleAgentId(), text: text))
    }

    func sendPrompt(_ text: String, images: [PromptImage]) async throws {
        guard !images.isEmpty else { return try await sendPrompt(text) }
        let agentId = try visibleAgentId()
        guard connectionState == .connected else { throw AppSessionError.notConnected }
        do {
            try await ImagePromptSender.send(text: text, images: images, uploader: uploader) { prompt in
                _ = try await self.request(.sendPrompt(agentId: agentId, text: prompt))
            }
        } catch let failure as ImagePromptUploadFailure {
            throw AppSessionError.uploadFailed(failure.error)
        }
    }

    func interrupt() async throws {
        try await request(.interrupt(agentId: try visibleAgentId()))
    }

    func loadOlderItems(for route: ChatTarget) {
        guard
            let current = chatStack.last(where: { $0.route == route }),
            current.hasMore,
            let before = current.before,
            !current.isLoading,
            !current.isLoadingOlder,
            let generation = chatGenerations[route]
        else { return }
        updateChat(route) { $0.isLoadingOlder = true }
        Task {
            do {
                let reply = try await request(.openChat(target: current.target, before: before, limit: Self.pageSize))
                guard chatGenerations[route] == generation else { return }
                guard case .chatPage(let page) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                prependOlder(page, to: route)
            } catch {
                guard chatGenerations[route] == generation else { return }
                updateChat(route) {
                    $0.isLoadingOlder = false
                    $0.failure = Self.sessionError(from: error)
                }
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
        if let agent = workspaces.agent(withId: agentId), agent.kind == AgentKind.codex, agent.controlAvailable != true {
            throw AppSessionError.controlUnavailable
        }
        return agentId
    }

    private func sendWithoutReply(_ message: ClientMessage) {
        Task { try? await request(message) }
    }

    private var stackEntries: [ChatStackEntry] {
        chatStack.map(\.stackEntry)
    }

    private func navigate(_ step: ChatNavigationStep) {
        switch step {
        case .stay:
            if let visible = visibleChat, visible.failure != nil {
                loadLatestPage(visible.route)
            }
        case .show(let path, let closing):
            for target in closing {
                sendWithoutReply(.closeChat(target: target))
            }
            let previous = chatStack
            departingChats = previous.filter { !path.contains($0.route) }
            chatStack = path.map { route in
                previous.first { $0.route == route } ?? ChatState(route: route, target: route, sessionId: sessionId(for: route))
            }
            for dropped in previous where !path.contains(dropped.route) {
                chatGenerations[dropped.route] = nil
            }
            for route in path where !previous.contains(where: { $0.route == route }) {
                loadLatestPage(route)
            }
        }
    }

    private func updateChat(_ route: ChatTarget, _ change: (inout ChatState) -> Void) {
        guard let index = chatStack.lastIndex(where: { $0.route == route }) else { return }
        change(&chatStack[index])
    }

    private func updateChats(target: ChatTarget, _ change: (inout ChatState) -> Void) {
        for index in chatStack.indices where chatStack[index].target == target {
            change(&chatStack[index])
        }
    }

    private func beginGeneration(for route: ChatTarget) -> Int {
        nextChatGeneration += 1
        chatGenerations[route] = nextChatGeneration
        return nextChatGeneration
    }

    private func sessionId(for target: ChatTarget) -> String? {
        switch target {
        case .agent(let agentId): workspaces.agent(withId: agentId)?.sessionId
        case .session(let sessionId), .codexThread(let sessionId): sessionId
        case .subagent(let sessionId, _): sessionId
        }
    }

    private func apply(_ state: ConnectionState) {
        let wasConnected = connectionState == .connected
        connectionState = state
        if pairing.apply(state) {
            coverWithPairing()
        }
        guard state == .connected else {
            foreground.connectionClosed()
            if wasConnected {
                AgentsActivityController.shared.socketClosed()
            }
            failAllReplies(with: .notConnected)
            if !isOpeningConnection {
                failChatWaitingForConnection()
            }
            return
        }
        if !wasConnected {
            reopenChatStack()
            sendForeground()
            AppNotifications.connectionOpened()
            AgentsActivityController.shared.socketOpened { [weak self] registration in
                await self?.registerLiveActivity(registration) ?? false
            }
        }
    }

    private func registerLiveActivity(_ registration: LiveActivityRegistration) async -> Bool {
        do {
            try await request(.registerLiveActivity(registration))
            return true
        } catch {
            return false
        }
    }

    private func coverWithPairing() {
        sheet = nil
        isDrawerOpen = false
        isInboxOpen = false
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
            usages[snapshot.provider] = snapshot
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
            updateChats(target: target) { $0.meta = meta }
        case .pending(let requests):
            pending.replace(with: requests)
        case .chatPage, .subagentList, .webServers, .ack, .pong, .error, .unknown:
            break
        }
    }

    private func applyTree(_ newWorkspaces: [WorkspaceNode]) {
        workspaces = newWorkspaces
        hasReceivedTree = true
        AgentsActivityController.shared.agentsChanged(newWorkspaces.allAgents)
        for current in chatStack {
            guard case .agent = current.target else { continue }
            switch ChatTargetTracking.change(for: current.target, knownSessionId: current.sessionId, in: newWorkspaces) {
            case .unchanged:
                break
            case .learnedSession(let sessionId):
                updateChat(current.route) { $0.sessionId = sessionId }
            case .sessionSwitched(let sessionId):
                updateChat(current.route) { $0.sessionId = sessionId }
                loadLatestPage(current.route)
            case .agentMoved(let agentId):
                updateChat(current.route) { $0.target = .agent(agentId) }
            }
        }
    }

    private func applyAgentStatus(agentId: AgentID, status: AgentStatus, title: String?) {
        workspaces.updateAgent(withId: agentId) { agent in
            agent.status = status
            if let title {
                agent.title = title
            }
        }
        AgentsActivityController.shared.agentsChanged(workspaces.allAgents)
        updateChats(target: .agent(agentId)) { chat in
            chat.meta?.status = status
            if let title {
                chat.meta?.title = title
            }
        }
    }

    private func appendToChat(target: ChatTarget, items: [ChatItem]) {
        updateChats(target: target) { chat in
            let knownIds = Set(chat.items.map(\.id))
            chat.items.append(contentsOf: items.filter { !knownIds.contains($0.id) })
        }
    }

    private func updateChat(target: ChatTarget, items: [ChatItem]) {
        updateChats(target: target) { chat in
            for item in items {
                guard let index = chat.items.firstIndex(where: { $0.id == item.id }) else { continue }
                chat.items[index] = item
            }
        }
    }

    private func reopenChatStack() {
        let reopening = ChatNavigation.reopening(stack: stackEntries)
        for current in chatStack where reopening.contains(current.target) {
            loadLatestPage(current.route)
        }
    }

    private var isOpeningConnection: Bool {
        switch connectionState {
        case .idle, .connecting: true
        case .connected, .waitingToRetry, .pairingRequired, .failed: false
        }
    }

    private func failChatWaitingForConnection() {
        for index in chatStack.indices where chatStack[index].isLoading {
            chatStack[index].isLoading = false
            chatStack[index].failure = .notConnected
        }
    }

    private func loadLatestPage(_ route: ChatTarget) {
        guard let current = chatStack.last(where: { $0.route == route }) else { return }
        let generation = beginGeneration(for: route)
        updateChat(route) {
            $0.isLoading = true
            $0.failure = nil
        }
        guard !isOpeningConnection else { return }
        Task {
            do {
                let reply = try await request(.openChat(target: current.target, limit: Self.pageSize))
                guard chatGenerations[route] == generation else { return }
                guard case .chatPage(let page) = reply else {
                    throw AppSessionError.unexpectedReply(type: reply.type)
                }
                replaceChat(route, with: page)
            } catch {
                guard chatGenerations[route] == generation else { return }
                updateChat(route) {
                    $0.isLoading = false
                    $0.failure = Self.sessionError(from: error)
                }
            }
        }
    }

    private func replaceChat(_ route: ChatTarget, with page: ChatPage) {
        guard let current = chatStack.last(where: { $0.route == route }) else { return }
        let replaced = ChatState(
            route: current.route,
            target: page.target,
            sessionId: sessionId(for: page.target) ?? current.sessionId,
            meta: page.meta,
            items: page.items,
            before: page.before,
            hasMore: page.hasMore,
            isLoading: false
        )
        updateChat(route) { $0 = replaced }
    }

    private func prependOlder(_ page: ChatPage, to route: ChatTarget) {
        updateChat(route) { chat in
            guard chat.target == page.target else { return }
            let knownIds = Set(chat.items.map(\.id))
            chat.items.insert(contentsOf: page.items.filter { !knownIds.contains($0.id) }, at: 0)
            chat.before = page.before
            chat.hasMore = page.hasMore
            chat.meta = page.meta
            chat.isLoadingOlder = false
        }
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
    static let codex = "codex"
}
