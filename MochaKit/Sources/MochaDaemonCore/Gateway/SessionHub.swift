import Foundation
import MochaProtocol
import os

let gatewayLogger = Logger(subsystem: "com.joaoalves.mocha", category: "gateway")

public struct SessionHubConfiguration: Sendable {
    public var hostName: String
    public var daemonVersion: String
    public var treeDebounce: Duration
    public var homeLiveRelease: Duration
    public var sshIdentity: SSHHostIdentity?

    public init(
        hostName: String = SessionHubConfiguration.defaultHostName,
        daemonVersion: String = DaemonVersion.current,
        treeDebounce: Duration = .milliseconds(150),
        homeLiveRelease: Duration = .seconds(30),
        sshIdentity: SSHHostIdentity? = nil
    ) {
        self.hostName = hostName
        self.daemonVersion = daemonVersion
        self.treeDebounce = treeDebounce
        self.homeLiveRelease = homeLiveRelease
        self.sshIdentity = sshIdentity
    }

    public static var defaultHostName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
}

public struct ConnectedClient: Sendable, Equatable {
    public let deviceId: DeviceID
    public let name: String
    public let connectedAt: Date

    public init(deviceId: DeviceID, name: String, connectedAt: Date) {
        self.deviceId = deviceId
        self.name = name
        self.connectedAt = connectedAt
    }
}

public struct FollowedSession: Sendable, Equatable {
    public let sessionId: String
    public let agentId: AgentID?

    public init(sessionId: String, agentId: AgentID?) {
        self.sessionId = sessionId
        self.agentId = agentId
    }
}

public actor SessionHub {
    static let defaultChatLimit = 60
    static let chatLimits = 1...200
    static let maxAuthenticationFailures = 3
    static let homeLiveLimit = 1

    enum OutboundFrame: Sendable {
        case text(String)
        case close(WebSocketCloseCode, String)
    }

    struct Foreground {
        var agentId: AgentID?
        var isActive: Bool
    }

    struct Client {
        let outbox: AsyncStream<OutboundFrame>.Continuation
        let writer: Task<Void, Never>
        var deviceId: DeviceID?
        var name: String?
        var connectedAt: Date?
        var failures = 0
        var isClosing = false
        var chats: [ChatTarget: OpenChat] = [:]
        var foreground: Foreground?

        var isAuthenticated: Bool {
            deviceId != nil
        }
    }

    struct OpenChat {
        let token: UUID
        var target: ChatTarget
        var sessionId: String?
        var subscription: TranscriptSubscription?
        var forwarder: Task<Void, Never>?
        var lastMeta: ChatMeta?
        var subagent: SubagentTranscript?
        var subagentMeta: TranscriptMeta?
        var cards: [String: ChatItem] = [:]
        var codexThreadId: String?
        var codexItems: [String: ChatItem] = [:]

        func cancel() {
            subscription?.cancel()
            forwarder?.cancel()
        }
    }

    struct LiveFollow {
        let token: UUID
        let sessionId: String
        var subscription: TranscriptSubscription?
        var forwarder: Task<Void, Never>?
        var release: Task<Void, Never>?

        func cancel() {
            subscription?.cancel()
            forwarder?.cancel()
            release?.cancel()
        }
    }

    let herdr: any HerdrBridging
    let transcripts: any TranscriptProviding
    let devices: DeviceStore
    let pairing: Pairing
    let usage: any UsageProviding
    let archive: any SessionArchiving
    let subagents: (any SubagentProviding)?
    let pending: (any PendingProviding)?
    let webServers: (any WebServerScanning)?
    let clock: any GatewayClock
    let configuration: SessionHubConfiguration
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    var baseTree: [WorkspaceNode] = []
    var herdrAvailable = false
    var metas: [String: TranscriptMeta] = [:]
    var clients: [UUID: Client] = [:]
    var isShuttingDown = false
    var usageSnapshot: UsageSnapshot?
    var archivedSessions: [ArchivedSession] = []
    var pluginContexts: [String: Double] = [:]
    var archivedAts: [String: Date] = [:]
    var reportedTurnStarts: [String: Date] = [:]
    var trackedSessions: [String: AgentSummary] = [:]
    var sessionServiceTasks: [Task<Void, Never>] = []
    var transcriptPaths: [String: String] = [:]
    var transcriptPathOrder: [String] = []
    var subagentStates: [String: SubagentState] = [:]
    var workflowStates: [String: WorkflowState] = [:]
    var runningSubagentCounts: [String: Int] = [:]
    var observedSubagentSessions: Set<String> = []
    var cardThrottles: [String: CardThrottle] = [:]
    var metaThrottles: [UUID: MetaThrottle] = [:]
    var subagentTasks: [Task<Void, Never>] = []
    var pendingRequests: [PendingRequest] = []
    var pendingDecisions: [AgentID: PendingDecision] = [:]
    let observedSessionUpdates: AsyncStream<Set<String>>
    let observedSessionContinuation: AsyncStream<Set<String>>.Continuation
    let liveActivityInputs: AsyncStream<LiveActivityInput>
    let liveActivityInputContinuation: AsyncStream<LiveActivityInput>.Continuation
    var liveActivityRegistrar: (any LiveActivityRegistering)?
    var codex: CodexService?
    var codexPanes: [AgentID: CodexPaneState] = [:]
    var codexConnected = false
    var codexUsage: UsageSnapshot?
    var storePendingRequests: [PendingRequest] = []
    var codexPendingRequests: [PendingRequest] = []
    var codexRefreshes: [String: Task<Void, Never>] = [:]
    let codexAlerts: AsyncStream<CodexAlert>
    let codexAlertContinuation: AsyncStream<CodexAlert>.Continuation

    private var lastSentTree: [WorkspaceNode] = []
    private var liveFollows: [AgentID: LiveFollow] = [:]
    private var metaSources: [String: UUID] = [:]
    private var hasSnapshot = false
    private var eventsTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var publishedOpenChats: Set<AgentID> = []
    private let openChatUpdates: AsyncStream<Set<AgentID>>
    private let openChatContinuation: AsyncStream<Set<AgentID>>.Continuation
    private var openChatPublisher: Task<Void, Never>?

    public init(
        herdr: any HerdrBridging,
        transcripts: any TranscriptProviding,
        devices: DeviceStore,
        pairing: Pairing,
        usage: any UsageProviding,
        archive: any SessionArchiving,
        subagents: (any SubagentProviding)? = nil,
        pending: (any PendingProviding)? = nil,
        webServers: (any WebServerScanning)? = nil,
        clock: any GatewayClock = SystemGatewayClock(),
        configuration: SessionHubConfiguration = SessionHubConfiguration()
    ) {
        self.herdr = herdr
        self.transcripts = transcripts
        self.devices = devices
        self.pairing = pairing
        self.usage = usage
        self.archive = archive
        self.subagents = subagents
        self.pending = pending
        self.webServers = webServers
        self.clock = clock
        self.configuration = configuration
        let (updates, continuation) = AsyncStream.makeStream(of: Set<AgentID>.self)
        openChatUpdates = updates
        openChatContinuation = continuation
        let (sessionUpdates, sessionContinuation) = AsyncStream.makeStream(of: Set<String>.self, bufferingPolicy: .bufferingNewest(1))
        observedSessionUpdates = sessionUpdates
        observedSessionContinuation = sessionContinuation
        let (liveActivityInputs, liveActivityInputContinuation) = AsyncStream.makeStream(
            of: LiveActivityInput.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.liveActivityInputs = liveActivityInputs
        self.liveActivityInputContinuation = liveActivityInputContinuation
        (codexAlerts, codexAlertContinuation) = AsyncStream.makeStream(of: CodexAlert.self)
    }

    public func start() async {
        guard eventsTask == nil, !isShuttingDown else { return }
        await startSessionServices()
        await startPendingUpdates()
        startCodexUpdates()
        startSubagentServices()
        let updates = openChatUpdates
        openChatPublisher = Task { [herdr] in
            for await ids in updates {
                await herdr.setOpenChats(ids)
            }
        }
        let events = herdr.events()
        let (ready, readyContinuation) = AsyncStream.makeStream(of: Void.self)
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.apply(event)
                readyContinuation.finish()
            }
            readyContinuation.finish()
        }
        for await _ in ready {}
    }

    public func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        let writers = Array(clients.keys).compactMap { close($0, error: nil, id: nil, code: .goingAway) }
        for writer in writers {
            await writer.value
        }
        eventsTask?.cancel()
        eventsTask = nil
        flushTask?.cancel()
        flushTask = nil
        for task in sessionServiceTasks {
            task.cancel()
        }
        sessionServiceTasks.removeAll()
        for task in subagentTasks {
            task.cancel()
        }
        subagentTasks.removeAll()
        observedSessionContinuation.finish()
        liveActivityInputContinuation.finish()
        codexAlertContinuation.finish()
        for task in codexRefreshes.values {
            task.cancel()
        }
        codexRefreshes.removeAll()
        for throttle in cardThrottles.values {
            throttle.pending?.cancel()
        }
        cardThrottles.removeAll()
        for throttle in metaThrottles.values {
            throttle.pending?.cancel()
        }
        metaThrottles.removeAll()
        for follow in liveFollows.values {
            follow.cancel()
        }
        liveFollows.removeAll()
        openChatContinuation.finish()
        openChatPublisher = nil
    }

    public func connectedClients() -> [ConnectedClient] {
        clients.values
            .compactMap { client -> ConnectedClient? in
                guard !client.isClosing, let deviceId = client.deviceId, let name = client.name, let connectedAt = client.connectedAt else {
                    return nil
                }
                return ConnectedClient(deviceId: deviceId, name: name, connectedAt: connectedAt)
            }
            .sorted { ($0.connectedAt, $0.deviceId) < ($1.connectedAt, $1.deviceId) }
    }

    public func followedSessions() -> [FollowedSession] {
        var followed: [String: FollowedSession] = [:]
        for client in clients.values {
            for chat in client.chats.values {
                guard let sessionId = chat.sessionId else { continue }
                switch chat.target {
                case .agent(let agentId):
                    followed[sessionId] = FollowedSession(sessionId: sessionId, agentId: agentId)
                case .session:
                    if followed[sessionId] == nil {
                        let agentId = TreeComposer.agents(in: baseTree).first { $0.sessionId == sessionId }?.id
                        followed[sessionId] = FollowedSession(sessionId: sessionId, agentId: agentId)
                    }
                case .codexThread, .subagent:
                    break
                }
            }
        }
        for (agentId, follow) in liveFollows {
            followed[follow.sessionId] = FollowedSession(sessionId: follow.sessionId, agentId: agentId)
        }
        return followed.values.sorted { $0.sessionId < $1.sessionId }
    }

    public func removeDevice(_ deviceId: DeviceID) async throws -> Bool {
        let writers = clients
            .filter { $0.value.deviceId == deviceId }
            .keys
            .compactMap { close($0, error: .deviceRemoved, id: nil, code: .policyViolation) }
        let removed = try await devices.remove(deviceId)
        for writer in writers {
            await writer.value
        }
        return removed
    }

    func composedTree() -> [WorkspaceNode] {
        let tree = TreeComposer.compose(
            baseTree,
            metas: metas,
            contexts: pluginContexts,
            archivedAts: archivedAts,
            runningSubagents: runningSubagentCounts,
            pendingCounts: pendingCounts()
        )
        return TreeComposer.codexOverlay(tree, panes: codexPanes, connected: codexConnected)
    }

    func composedAgent(_ id: AgentID) -> AgentSummary? {
        guard let agent = TreeComposer.agent(id, in: baseTree) else { return nil }
        return composedSummary(agent)
    }

    func composedSummary(_ agent: AgentSummary) -> AgentSummary {
        var agent = TreeComposer.codexSummary(agent, pane: codexPanes[agent.id], connected: codexConnected)
        agent.pendingCount = pendingRequests.count { $0.agentId == agent.id }
        guard let sessionId = agent.sessionId else { return agent }
        return TreeComposer.summary(
            agent,
            meta: metas[sessionId],
            contextUsedPercent: pluginContexts[sessionId],
            archivedAt: archivedAts[sessionId],
            runningSubagents: runningSubagentCounts[sessionId]
        )
    }

    func remember(_ meta: TranscriptMeta, forSession sessionId: String, source: UUID?) {
        if let owner = metaSources[sessionId], owner != source, isActiveMetaSource(owner, forSession: sessionId) {
            return
        }
        if let source {
            metaSources[sessionId] = source
        } else if followedSessionIds().contains(sessionId) {
            return
        }
        guard metas[sessionId] != meta else { return }
        metas[sessionId] = meta
        refreshChatMetas()
        scheduleTreeFlush()
    }

    func publishOpenChats() {
        publishObservedSessions()
        var ids: Set<AgentID> = []
        for client in clients.values {
            for target in client.chats.keys {
                if case .agent(let agentId) = target {
                    ids.insert(agentId)
                }
            }
        }
        guard ids != publishedOpenChats else { return }
        publishedOpenChats = ids
        openChatContinuation.yield(ids)
    }

    func scheduleTreeFlush() {
        guard flushTask == nil, !isShuttingDown else { return }
        let clock = clock
        let delay = configuration.treeDebounce
        flushTask = Task { [weak self] in
            guard (try? await clock.sleep(for: delay)) != nil else { return }
            await self?.scheduledFlushFired()
        }
    }

    private func apply(_ event: HerdrBridgeEvent) async {
        switch event {
        case .snapshot(let tree, let available):
            baseTree = tree
            setAvailability(available)
            updateLiveFollows()
            await trackSessions()
            if hasSnapshot {
                scheduleTreeFlush()
            } else {
                hasSnapshot = true
                await flushTree()
            }
        case .treeChanged(let tree):
            baseTree = tree
            updateLiveFollows()
            await trackSessions()
            scheduleTreeFlush()
        case .agentStatus(let agentId, let status, let title):
            baseTree = TreeComposer.updatingAgent(agentId, in: baseTree) { $0.status = status }
            if codexPanes[agentId] == nil {
                broadcast(.agentStatus(agentId: agentId, status: status, title: statusTitle(for: agentId, eventTitle: title)))
            }
            updateLiveFollows()
            refreshChatMetas()
            scheduleTreeFlush()
        case .sessionChanged(let agentId, let sessionId):
            baseTree = TreeComposer.updatingAgent(agentId, in: baseTree) { $0.sessionId = sessionId }
            updateLiveFollows()
            await trackSessions()
            await switchChats(ofAgent: agentId, toSession: sessionId)
            scheduleTreeFlush()
        case .availability(let available):
            setAvailability(available)
            await trackSessions()
        case .paneMoved(let from, let to):
            moveAgent(from: from, to: to)
            await trackSessions()
        }
    }

    private func setAvailability(_ available: Bool) {
        guard herdrAvailable != available else { return }
        herdrAvailable = available
        broadcast(.herdrStatus(connected: available))
    }

    private func statusTitle(for agentId: AgentID, eventTitle: String?) -> String? {
        let agent = TreeComposer.agent(agentId, in: baseTree)
        if let sessionId = agent?.sessionId, let title = metas[sessionId]?.title, !title.isEmpty {
            return title
        }
        if let eventTitle, !eventTitle.isEmpty {
            return eventTitle
        }
        return agent?.title
    }

    private func moveAgent(from oldId: AgentID, to newId: AgentID) {
        guard oldId != newId else { return }
        baseTree = TreeComposer.updatingAgent(oldId, in: baseTree) { $0.id = newId }
        if let follow = liveFollows.removeValue(forKey: oldId) {
            liveFollows[newId]?.cancel()
            liveFollows[newId] = follow
        }
        for clientId in Array(clients.keys) {
            if clients[clientId]?.foreground?.agentId == oldId {
                clients[clientId]?.foreground?.agentId = newId
            }
            guard var chat = clients[clientId]?.chats.removeValue(forKey: .agent(oldId)) else { continue }
            chat.target = .agent(newId)
            clients[clientId]?.chats[.agent(newId)]?.cancel()
            clients[clientId]?.chats[.agent(newId)] = chat
        }
        publishOpenChats()
        scheduleTreeFlush()
    }

    private func scheduledFlushFired() async {
        flushTask = nil
        await flushTree()
    }

    private func flushTree() async {
        await retainCodexPanes()
        await refreshUnfollowedMetas()
        pruneMetas()
        publishObservedSessions()
        await refreshSessionState()
        let tree = composedTree()
        if tree != lastSentTree {
            lastSentTree = tree
            broadcast(.treeChanged(workspaces: tree))
        }
        publishLiveActivityInput(tree)
        refreshChatMetas()
    }

    private func refreshUnfollowedMetas() async {
        let sessionIds = Set(TreeComposer.agents(in: baseTree).compactMap(\.sessionId))
        for sessionId in sessionIds.subtracting(followedSessionIds()).sorted() {
            let meta = await transcripts.meta(forSession: transcriptSession(sessionId))
            guard !followedSessionIds().contains(sessionId) else { continue }
            metas[sessionId] = meta
        }
    }

    private func followedSessionIds() -> Set<String> {
        var sessionIds: Set<String> = []
        for follow in liveFollows.values where follow.subscription != nil {
            sessionIds.insert(follow.sessionId)
        }
        for client in clients.values {
            for chat in client.chats.values where chat.subscription != nil {
                if let sessionId = chat.sessionId {
                    sessionIds.insert(sessionId)
                }
            }
        }
        return sessionIds
    }

    private func pruneMetas() {
        var referenced = Set(TreeComposer.agents(in: baseTree).compactMap(\.sessionId))
        for follow in liveFollows.values {
            referenced.insert(follow.sessionId)
        }
        for client in clients.values {
            for chat in client.chats.values {
                if let sessionId = chat.sessionId {
                    referenced.insert(sessionId)
                }
            }
        }
        metas = metas.filter { referenced.contains($0.key) }
        metaSources = metaSources.filter { referenced.contains($0.key) }
    }

    func updateLiveFollows() {
        guard !isShuttingDown else { return }
        var wanted: [AgentID: String] = [:]
        for agent in TreeComposer.agents(in: baseTree) where agent.kind == TreeComposer.claudeKind {
            guard let sessionId = agent.sessionId else { continue }
            if agent.status == .working || agent.status == .blocked || runningSubagentCounts[sessionId, default: 0] > 0 {
                wanted[agent.id] = sessionId
            }
        }
        for (agentId, sessionId) in wanted {
            if var follow = liveFollows[agentId], follow.sessionId == sessionId {
                follow.release?.cancel()
                follow.release = nil
                liveFollows[agentId] = follow
                continue
            }
            liveFollows[agentId]?.cancel()
            startLiveFollow(agentId: agentId, sessionId: sessionId)
        }
        for (agentId, follow) in liveFollows where wanted[agentId] == nil && follow.release == nil {
            liveFollows[agentId]?.release = scheduleRelease(of: follow.token)
        }
    }

    private func startLiveFollow(agentId: AgentID, sessionId: String) {
        let token = UUID()
        liveFollows[agentId] = LiveFollow(token: token, sessionId: sessionId)
        let transcripts = transcripts
        let session = transcriptSession(sessionId)
        Task { [weak self] in
            let subscription = try? await transcripts.open(session: session, limit: Self.homeLiveLimit)
            guard let self else {
                subscription?.cancel()
                return
            }
            await self.liveFollowOpened(token: token, subscription: subscription)
        }
    }

    private func liveFollowOpened(token: UUID, subscription: TranscriptSubscription?) {
        guard let key = liveFollowKey(for: token) else {
            subscription?.cancel()
            return
        }
        guard let subscription, var follow = liveFollows[key], follow.subscription == nil else {
            liveFollows[key]?.cancel()
            liveFollows[key] = nil
            return
        }
        let sessionId = follow.sessionId
        follow.subscription = subscription
        follow.forwarder = Task { [weak self] in
            for await delta in subscription.deltas {
                guard case .meta(let meta) = delta else { continue }
                await self?.liveMeta(meta, token: token, sessionId: sessionId)
            }
        }
        liveFollows[key] = follow
        remember(subscription.page.meta, forSession: sessionId, source: token)
    }

    private func liveMeta(_ meta: TranscriptMeta, token: UUID, sessionId: String) {
        guard liveFollowKey(for: token) != nil else { return }
        remember(meta, forSession: sessionId, source: token)
    }

    private func isActiveMetaSource(_ token: UUID, forSession sessionId: String) -> Bool {
        if liveFollows.values.contains(where: { $0.token == token && $0.sessionId == sessionId && $0.subscription != nil }) {
            return true
        }
        return clients.values.contains { client in
            client.chats.values.contains { $0.token == token && $0.sessionId == sessionId && $0.subscription != nil }
        }
    }

    private func scheduleRelease(of token: UUID) -> Task<Void, Never> {
        let clock = clock
        let delay = configuration.homeLiveRelease
        return Task { [weak self] in
            guard (try? await clock.sleep(for: delay)) != nil else { return }
            await self?.releaseLiveFollow(token: token)
        }
    }

    private func releaseLiveFollow(token: UUID) {
        guard let key = liveFollowKey(for: token), let follow = liveFollows[key], follow.release != nil else { return }
        liveFollows[key] = nil
        follow.subscription?.cancel()
        follow.forwarder?.cancel()
    }

    private func liveFollowKey(for token: UUID) -> AgentID? {
        liveFollows.first { $0.value.token == token }?.key
    }
}
