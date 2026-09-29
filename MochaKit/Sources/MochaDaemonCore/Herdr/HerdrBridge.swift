import Foundation
import MochaHerdr
import MochaProtocol
import os

let herdrLogger = Logger(subsystem: "com.joaoalves.mocha", category: "herdr")

public actor HerdrBridge: HerdrBridging {
    public static let interruptKeys = ["Escape"]
    public static let newAgentKind = "claude"
    public static let newAgentNamePrefix = "mocha-"
    public static let codexAgentKind = "codex"
    static let codexStartTimeout: Duration = .seconds(4)
    public static let readyStatuses: [HerdrAgentStatus] = [.idle, .blocked]

    private struct PaneSubscription {
        let token: UUID
        var subscription: HerdrEventSubscription?
        let task: Task<Void, Never>
    }

    private struct ScheduledTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    let client: HerdrClient
    private let git: any GitInspecting
    let configuration: HerdrBridgeConfiguration
    private let hub = HerdrBridgeEventHub()

    private var runTask: Task<Void, Never>?
    private var globalSubscription: HerdrEventSubscription?
    private var generation = 0
    private var available = false
    private var currentServerInfo: HerdrServerInfo?
    private var state = HerdrState()
    private var paneSubscriptions: [String: PaneSubscription] = [:]
    private var movedPanes: [AgentID: AgentID] = [:]
    private var openChats: Set<AgentID> = []
    private var snapshotRefresh: ScheduledTask?
    private var treeRefresh: ScheduledTask?
    private var reconciliation: Task<Void, Never>?
    private var updateProbes: [String: ScheduledTask] = [:]
    private var pendingUpdateProbes: Set<String> = []
    private var detectionProbes: [String: ScheduledTask] = [:]
    private var sessionProbes: [String: ScheduledTask] = [:]
    private var treeDerivations = 0
    private var publishedDerivation = 0
    private var reservedAgentNames: Set<String> = []

    public init(
        client: HerdrClient = HerdrClient(),
        git: any GitInspecting = GitInspector(),
        configuration: HerdrBridgeConfiguration = HerdrBridgeConfiguration()
    ) {
        self.client = client
        self.git = git
        self.configuration = configuration
    }

    public func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.run()
        }
    }

    public func stop() async {
        let task = runTask
        runTask = nil
        task?.cancel()
        disconnect()
        await task?.value
    }

    public nonisolated func events() -> AsyncStream<HerdrBridgeEvent> {
        hub.subscribe()
    }

    public var isAvailable: Bool {
        available
    }

    public func tree() -> [WorkspaceNode] {
        hub.tree
    }

    public var serverInfo: HerdrServerInfo? {
        currentServerInfo
    }

    public func workspaceRoots() -> [WorkspaceRoot] {
        state.workspaces.compactMap { workspace in
            HerdrTreeBuilder.workspaceDirectory(workspace, in: state).map {
                WorkspaceRoot(workspaceId: workspace.workspaceId, path: $0, isCheckout: workspace.worktree?.checkoutPath != nil)
            }
        }
    }

    public func agent(_ id: AgentID) -> HerdrAgent? {
        guard let pane = state.pane(id), let kind = pane.agent else { return nil }
        return HerdrAgent(
            paneId: pane.paneId,
            workspaceId: pane.workspaceId,
            kind: kind,
            status: HerdrTreeBuilder.agentStatus(pane.agentStatus),
            sessionId: pane.sessionId,
            cwd: pane.cwd,
            foregroundCwd: pane.foregroundCwd,
            terminalTitle: pane.terminalTitleStripped
        )
    }

    public func resolve(_ id: AgentID) -> AgentID {
        var current = id
        var visited: Set<AgentID> = [id]
        while let next = movedPanes[current], visited.insert(next).inserted {
            current = next
        }
        return current
    }

    public func prompt(_ id: AgentID, text: String) async throws {
        try await ensureScreenFree(id, strict: false)
        try await command { client in
            _ = try await client.agentPrompt(target: id, text: text)
        }
    }

    public func interrupt(_ id: AgentID) async throws {
        try await command { client in
            try await client.agentSendKeys(target: id, keys: Self.interruptKeys)
        }
    }

    public func setOpenChats(_ ids: Set<AgentID>) {
        openChats = ids
        updateReconciliation()
    }

    public func refreshAgent(_ id: AgentID, expectingSession sessionId: String) {
        let paneId = resolve(id)
        guard available, state.pane(paneId) != nil else { return }
        sessionProbes.removeValue(forKey: paneId)?.task.cancel()
        let token = UUID()
        let cycle = generation
        let delays = configuration.sessionStartProbeDelays
        let task = Task { [weak self] in
            var elapsed: Duration = .zero
            for delay in delays {
                guard (try? await Task.sleep(for: delay - elapsed)) != nil else { return }
                elapsed = delay
                guard let self, await self.needsSessionStartProbe(paneId, expecting: sessionId, token: token, cycle: cycle) else {
                    return
                }
                await self.refreshAgent(paneId, cycle: cycle)
            }
            await self?.sessionProbesFinished(paneId, token: token)
        }
        sessionProbes[paneId] = ScheduledTask(token: token, task: task)
    }

    public func refreshDirtyState(ofAgent id: AgentID) async {
        let paneId = resolve(id)
        guard let pane = state.pane(paneId),
            let workspace = state.workspace(pane.workspaceId),
            let directory = HerdrTreeBuilder.workspaceDirectory(workspace, in: state)
        else { return }
        await git.invalidateDirty(at: directory)
        scheduleTreeRefresh()
    }

    public func newAgentTab(in workspaceId: WorkspaceID) async throws -> AgentID {
        guard available else { throw HerdrBridgeError.unavailable }
        guard let workspace = state.workspace(workspaceId) else { throw HerdrBridgeError.workspaceNotFound }
        let directory = HerdrTreeBuilder.workspaceDirectory(workspace, in: state)
        let created = try await command { client in
            try await client.tabCreate(workspaceId: workspaceId, cwd: directory)
        }
        let paneId = created.rootPane.paneId
        let statusEvents = try? await client.subscribe([.agentStatusChanged(paneId: paneId)])
        defer { statusEvents?.cancel() }
        let namesInUse = try await command { client in
            try await client.agentList().compactMap(\.name)
        }
        let name = Self.newAgentName(excluding: reservedAgentNames.union(namesInUse))
        reservedAgentNames.insert(name)
        defer { reservedAgentNames.remove(name) }
        _ = try await command { client in
            try await client.agentStart(name: name, kind: Self.newAgentKind, paneId: paneId, args: [])
        }
        await waitUntilReady(paneId, statusEvents: statusEvents)
        if available {
            await refreshSnapshotNow(cycle: generation)
        }
        return paneId
    }

    public func newCodexTab(in workspaceId: WorkspaceID, remote: String) async throws -> (paneId: AgentID, cwd: String?) {
        guard available else { throw HerdrBridgeError.unavailable }
        guard let workspace = state.workspace(workspaceId) else { throw HerdrBridgeError.workspaceNotFound }
        let directory = HerdrTreeBuilder.workspaceDirectory(workspace, in: state)
        let created = try await command { client in
            try await client.tabCreate(workspaceId: workspaceId, cwd: directory)
        }
        let paneId = created.rootPane.paneId
        let namesInUse = try await command { client in
            try await client.agentList().compactMap(\.name)
        }
        let name = Self.newAgentName(excluding: reservedAgentNames.union(namesInUse))
        reservedAgentNames.insert(name)
        defer { reservedAgentNames.remove(name) }
        do {
            _ = try await command { client in
                try await client.agentStart(
                    name: name,
                    kind: Self.codexAgentKind,
                    paneId: paneId,
                    args: ["--remote", remote],
                    timeout: Self.codexStartTimeout
                )
            }
        } catch HerdrBridgeError.herdr(code: "timeout", _) {}
        if available {
            await refreshSnapshotNow(cycle: generation)
        }
        return (paneId, directory)
    }

    static func newAgentName(excluding namesInUse: Set<String>) -> String {
        var number = 1
        while namesInUse.contains("\(newAgentNamePrefix)\(number)") {
            number += 1
        }
        return "\(newAgentNamePrefix)\(number)"
    }

    private func waitUntilReady(_ paneId: String, statusEvents: HerdrEventSubscription?) async {
        let client = self.client
        let timeout = configuration.newAgentReadyTimeout
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                try? await Task.sleep(for: timeout)
                return true
            }
            group.addTask {
                (try? await client.agentWait(target: paneId, until: Self.readyStatuses, timeout: timeout)) != nil
            }
            if let statusEvents {
                group.addTask {
                    for await event in statusEvents.events {
                        if case .agentStatusChanged(_, _, let status, _) = event, Self.readyStatuses.contains(status) {
                            return true
                        }
                    }
                    return false
                }
            }
            for await isReady in group where isReady {
                group.cancelAll()
                return
            }
        }
    }

    func command<Value: Sendable>(_ operation: @Sendable (HerdrClient) async throws -> Value) async throws -> Value {
        guard available else { throw HerdrBridgeError.unavailable }
        do {
            return try await operation(client)
        } catch let error as HerdrClientError {
            throw bridgeError(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HerdrBridgeError.herdr(code: "internal", message: String(describing: error))
        }
    }

    private func bridgeError(for error: HerdrClientError) -> HerdrBridgeError {
        switch error {
        case .connectionFailed:
            connectionLost()
            return .unavailable
        case .server(let serverError):
            switch serverError.code {
            case .agentBlocked:
                return .agentBlocked
            case .agentNotFound, .paneNotFound:
                return .agentNotFound
            default:
                return .herdr(code: serverError.code.rawValue, message: serverError.message)
            }
        case .timeout(let method):
            return .herdr(code: "timeout", message: "O Herdr não respondeu a \(method) a tempo.")
        case .closedWithoutResponse(let method):
            return .herdr(code: "closed", message: "O Herdr fechou a conexão sem responder a \(method).")
        case .invalidResponse(let method, let detail):
            return .herdr(code: "invalid_response", message: "Resposta inválida do Herdr para \(method): \(detail)")
        }
    }

    private func run() async {
        while !Task.isCancelled {
            await connectAndServe()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: configuration.reconnectInterval)
        }
    }

    private func connectAndServe() async {
        let cycle = generation
        let subscription: HerdrEventSubscription
        do {
            subscription = try await client.subscribe(HerdrSubscription.globalLifecycle)
        } catch {
            herdrLogger.debug("herdr subscription failed: \(String(describing: error), privacy: .public)")
            disconnect()
            return
        }
        guard cycle == generation, !Task.isCancelled else {
            subscription.cancel()
            return
        }
        globalSubscription = subscription
        do {
            let pong = try await client.ping()
            guard cycle == generation else { return }
            record(pong)
            let snapshot = try await client.sessionSnapshot()
            guard cycle == generation, !Task.isCancelled else { return }
            applySnapshot(snapshot)
            await publishTreeNow()
            guard cycle == generation else { return }
            setAvailable(true)
            syncPaneSubscriptions()
            updateReconciliation()
        } catch {
            herdrLogger.error("herdr bootstrap failed: \(String(describing: error), privacy: .public)")
            disconnect()
            return
        }
        for await event in subscription.events {
            guard cycle == generation else { break }
            handle(event)
        }
        guard cycle == generation else { return }
        herdrLogger.error("herdr global subscription ended")
        disconnect()
    }

    private func record(_ pong: HerdrPong) {
        let info = HerdrServerInfo(version: pong.version, protocolVersion: pong.protocolVersion)
        currentServerInfo = info
        if let warning = info.protocolWarning {
            herdrLogger.error("\(warning, privacy: .public)")
        }
    }

    private func disconnect() {
        generation += 1
        globalSubscription?.cancel()
        globalSubscription = nil
        for subscription in paneSubscriptions.values {
            subscription.subscription?.cancel()
            subscription.task.cancel()
        }
        paneSubscriptions.removeAll()
        snapshotRefresh?.task.cancel()
        snapshotRefresh = nil
        for probe in updateProbes.values {
            probe.task.cancel()
        }
        updateProbes.removeAll()
        pendingUpdateProbes.removeAll()
        for probe in detectionProbes.values {
            probe.task.cancel()
        }
        detectionProbes.removeAll()
        for probe in sessionProbes.values {
            probe.task.cancel()
        }
        sessionProbes.removeAll()
        reconciliation?.cancel()
        reconciliation = nil
        setAvailable(false)
    }

    private func connectionLost() {
        globalSubscription?.cancel()
    }

    private func setAvailable(_ value: Bool) {
        guard available != value else { return }
        available = value
        hub.publish(.availability(value))
    }

    private func handle(_ event: HerdrEvent) {
        switch event {
        case .workspaceRenamed(let workspaceId, let label):
            if state.renameWorkspace(workspaceId, label: label) {
                scheduleTreeRefresh()
            }
        case .tabRenamed(let tabId, _, let label):
            if state.renameTab(tabId, label: label) {
                scheduleTreeRefresh()
            }
        case .paneUpdated(let pane):
            applyPaneUpdate(pane)
        case .paneClosed(let paneId, _), .paneExited(let paneId, _):
            closePaneSubscription(paneId)
        case .paneMoved(let previousPaneId, let pane):
            applyPaneMove(from: previousPaneId, to: pane)
        case .paneAgentDetected(let paneId, _, _, let released):
            if released {
                closePaneSubscription(paneId)
            } else {
                openPaneSubscription(paneId)
                scheduleDetectionProbes(paneId)
            }
        case .agentStatusChanged, .structural, .ignored:
            break
        }
        if event.requiresSnapshot {
            scheduleSnapshotRefresh()
        }
    }

    private func handlePaneEvent(_ event: HerdrEvent, cycle: Int) {
        guard cycle == generation, case .agentStatusChanged(let paneId, _, let status, let agent) = event else { return }
        applyStatus(status, agent: agent, to: paneId)
    }

    private func applyStatus(_ status: HerdrAgentStatus, agent: String?, to paneId: String) {
        guard let pane = state.pane(paneId) else { return }
        state.updatePane(paneId) { pane in
            if let agent {
                pane.agent = agent
            }
            pane.agentStatus = status
        }
        guard pane.agentStatus != status else { return }
        hub.publish(.agentStatus(paneId, HerdrTreeBuilder.agentStatus(status), title: pane.terminalTitleStripped))
        scheduleTreeRefresh()
        updateReconciliation()
    }

    private func applyPaneUpdate(_ update: HerdrPane) {
        guard let current = state.pane(update.paneId) else { return }
        var changed = false
        state.updatePane(update.paneId) { pane in
            if pane.terminalTitleStripped != update.terminalTitleStripped {
                pane.terminalTitleStripped = update.terminalTitleStripped
                changed = true
            }
            if pane.cwd != update.cwd {
                pane.cwd = update.cwd
                changed = true
            }
            if pane.foregroundCwd != update.foregroundCwd {
                pane.foregroundCwd = update.foregroundCwd
                changed = true
            }
            if let session = update.agentSession, pane.agentSession != session {
                pane.agentSession = session
                changed = true
            }
        }
        if let session = update.sessionId, session != current.sessionId {
            hub.publish(.sessionChanged(update.paneId, sessionId: session))
        }
        if changed {
            scheduleTreeRefresh()
        }
        if current.agent != nil || update.agent != nil {
            scheduleUpdateProbe(update.paneId)
        }
    }

    private func applyPaneMove(from previousPaneId: String, to pane: HerdrPane) {
        for (oldId, newId) in movedPanes where newId == previousPaneId {
            movedPanes[oldId] = pane.paneId
        }
        movedPanes[previousPaneId] = pane.paneId
        let hadSubscription = paneSubscriptions[previousPaneId] != nil
        closePaneSubscription(previousPaneId)
        state.replacePane(previousPaneId, with: pane)
        hub.publish(.paneMoved(from: previousPaneId, to: pane.paneId))
        if pane.agent != nil || hadSubscription {
            openPaneSubscription(pane.paneId)
        }
        scheduleTreeRefresh()
    }

    private func applyAgentInfo(_ info: HerdrPane) {
        guard let current = state.pane(info.paneId) else { return }
        var changed = false
        state.updatePane(info.paneId) { pane in
            if let agent = info.agent, pane.agent != agent {
                pane.agent = agent
                changed = true
            }
            if pane.agentStatus != info.agentStatus {
                pane.agentStatus = info.agentStatus
                changed = true
            }
            if let session = info.agentSession, pane.agentSession != session {
                pane.agentSession = session
                changed = true
            }
            if let title = info.terminalTitleStripped, pane.terminalTitleStripped != title {
                pane.terminalTitleStripped = title
                changed = true
            }
            if let cwd = info.cwd, pane.cwd != cwd {
                pane.cwd = cwd
                changed = true
            }
            if let foregroundCwd = info.foregroundCwd, pane.foregroundCwd != foregroundCwd {
                pane.foregroundCwd = foregroundCwd
                changed = true
            }
        }
        if current.agentStatus != info.agentStatus {
            hub.publish(
                .agentStatus(
                    info.paneId,
                    HerdrTreeBuilder.agentStatus(info.agentStatus),
                    title: info.terminalTitleStripped ?? current.terminalTitleStripped
                )
            )
            updateReconciliation()
        }
        if let session = info.sessionId, session != current.sessionId {
            hub.publish(.sessionChanged(info.paneId, sessionId: session))
        }
        if changed {
            scheduleTreeRefresh()
        }
    }

    private func applySnapshot(_ snapshot: HerdrSessionSnapshot) {
        let previous = state
        state = HerdrState(snapshot: snapshot)
        for pane in state.panes where pane.agent != nil {
            guard let old = previous.pane(pane.paneId) else { continue }
            if old.agentStatus != pane.agentStatus {
                hub.publish(.agentStatus(pane.paneId, HerdrTreeBuilder.agentStatus(pane.agentStatus), title: pane.terminalTitleStripped))
            }
            if let session = pane.sessionId, session != old.sessionId {
                hub.publish(.sessionChanged(pane.paneId, sessionId: session))
            }
        }
    }

    private func syncPaneSubscriptions() {
        let known = Set(state.panes.map(\.paneId))
        for paneId in paneSubscriptions.keys where !known.contains(paneId) {
            closePaneSubscription(paneId)
        }
        for paneId in state.agentPaneIds where paneSubscriptions[paneId] == nil {
            openPaneSubscription(paneId)
        }
    }

    private func openPaneSubscription(_ paneId: String) {
        guard available, paneSubscriptions[paneId] == nil else { return }
        let token = UUID()
        let cycle = generation
        let client = self.client
        let task = Task { [weak self] in
            let subscription: HerdrEventSubscription
            do {
                subscription = try await client.subscribe([.agentStatusChanged(paneId: paneId)])
            } catch {
                await self?.paneSubscriptionFailed(paneId, token: token, error: error)
                return
            }
            guard let self, await self.attach(subscription, to: paneId, token: token) else {
                subscription.cancel()
                return
            }
            await self.refreshAgent(paneId, cycle: cycle)
            for await event in subscription.events {
                await self.handlePaneEvent(event, cycle: cycle)
            }
            await self.paneSubscriptionEnded(paneId, token: token)
        }
        paneSubscriptions[paneId] = PaneSubscription(token: token, subscription: nil, task: task)
    }

    private func attach(_ subscription: HerdrEventSubscription, to paneId: String, token: UUID) -> Bool {
        guard paneSubscriptions[paneId]?.token == token else { return false }
        paneSubscriptions[paneId]?.subscription = subscription
        return true
    }

    private func paneSubscriptionFailed(_ paneId: String, token: UUID, error: any Error) {
        guard paneSubscriptions[paneId]?.token == token else { return }
        paneSubscriptions[paneId] = nil
        herdrLogger.debug("herdr pane subscription \(paneId, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        if let error = error as? HerdrClientError, error.isConnectionFailure {
            connectionLost()
        }
    }

    private func paneSubscriptionEnded(_ paneId: String, token: UUID) {
        guard paneSubscriptions[paneId]?.token == token else { return }
        paneSubscriptions[paneId] = nil
    }

    private func closePaneSubscription(_ paneId: String) {
        if let subscription = paneSubscriptions.removeValue(forKey: paneId) {
            subscription.subscription?.cancel()
            subscription.task.cancel()
        }
        updateProbes.removeValue(forKey: paneId)?.task.cancel()
        pendingUpdateProbes.remove(paneId)
        detectionProbes.removeValue(forKey: paneId)?.task.cancel()
        sessionProbes.removeValue(forKey: paneId)?.task.cancel()
    }

    private func refreshAgent(_ paneId: String, cycle: Int) async {
        guard cycle == generation else { return }
        do {
            let info = try await client.agentGet(target: paneId)
            guard cycle == generation else { return }
            applyAgentInfo(info)
        } catch {
            handleRequestFailure(error)
        }
    }

    private func handleRequestFailure(_ error: any Error) {
        if let error = error as? HerdrClientError, error.isConnectionFailure {
            connectionLost()
        } else {
            herdrLogger.debug("herdr request failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleSnapshotRefresh() {
        guard available, snapshotRefresh == nil else { return }
        let token = UUID()
        let cycle = generation
        let delay = configuration.snapshotDebounce
        let task = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            await self?.refreshSnapshot(token: token, cycle: cycle)
        }
        snapshotRefresh = ScheduledTask(token: token, task: task)
    }

    private func refreshSnapshot(token: UUID, cycle: Int) async {
        guard snapshotRefresh?.token == token else { return }
        snapshotRefresh = nil
        await refreshSnapshotNow(cycle: cycle)
    }

    private func refreshSnapshotNow(cycle: Int) async {
        guard cycle == generation else { return }
        do {
            let snapshot = try await client.sessionSnapshot()
            guard cycle == generation else { return }
            applySnapshot(snapshot)
            syncPaneSubscriptions()
            scheduleTreeRefresh()
            updateReconciliation()
        } catch {
            handleRequestFailure(error)
        }
    }

    private func scheduleTreeRefresh() {
        guard treeRefresh == nil else { return }
        let token = UUID()
        let delay = configuration.treeDebounce
        let task = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            await self?.refreshTree(token: token)
        }
        treeRefresh = ScheduledTask(token: token, task: task)
    }

    private func refreshTree(token: UUID) async {
        guard treeRefresh?.token == token else { return }
        treeRefresh = nil
        await publishTreeNow()
    }

    private func publishTreeNow() async {
        treeDerivations += 1
        let derivation = treeDerivations
        let snapshot = state
        let gitSnapshot = await collectGit(for: snapshot)
        let tree = HerdrTreeBuilder.build(state: snapshot, git: gitSnapshot)
        guard derivation > publishedDerivation else { return }
        publishedDerivation = derivation
        guard tree != hub.tree else { return }
        hub.publish(.treeChanged(tree))
    }

    private func collectGit(for state: HerdrState) async -> HerdrGitSnapshot {
        let workspaceDirectories = HerdrTreeBuilder.workspaceDirectories(in: state)
        let directories = workspaceDirectories.union(HerdrTreeBuilder.agentDirectories(in: state))
        let git = self.git
        return await withTaskGroup(of: (directory: String, branch: String?, isDirty: Bool).self) { group in
            for directory in directories {
                let checksDirty = workspaceDirectories.contains(directory)
                group.addTask {
                    let branch = await git.branch(at: directory)
                    guard checksDirty, branch != nil else { return (directory, branch, false) }
                    return (directory, branch, await git.isDirty(at: directory))
                }
            }
            var snapshot = HerdrGitSnapshot()
            for await result in group {
                if let branch = result.branch {
                    snapshot.branches[result.directory] = branch
                }
                if result.isDirty {
                    snapshot.dirtyDirectories.insert(result.directory)
                }
            }
            return snapshot
        }
    }

    private func scheduleUpdateProbe(_ paneId: String) {
        guard available else { return }
        guard updateProbes[paneId] == nil else {
            pendingUpdateProbes.insert(paneId)
            return
        }
        let token = UUID()
        let cycle = generation
        let delay = configuration.paneUpdateProbeDelay
        let task = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            await self?.runUpdateProbe(paneId, token: token, cycle: cycle)
        }
        updateProbes[paneId] = ScheduledTask(token: token, task: task)
    }

    private func runUpdateProbe(_ paneId: String, token: UUID, cycle: Int) async {
        guard updateProbes[paneId]?.token == token else { return }
        updateProbes[paneId] = nil
        await refreshAgent(paneId, cycle: cycle)
        if pendingUpdateProbes.remove(paneId) != nil, cycle == generation {
            scheduleUpdateProbe(paneId)
        }
    }

    private func scheduleDetectionProbes(_ paneId: String) {
        guard available else { return }
        detectionProbes.removeValue(forKey: paneId)?.task.cancel()
        let token = UUID()
        let cycle = generation
        let delays = configuration.agentDetectedProbeDelays
        let task = Task { [weak self] in
            var elapsed: Duration = .zero
            for delay in delays {
                guard (try? await Task.sleep(for: delay - elapsed)) != nil else { return }
                elapsed = delay
                guard let self, await self.needsSessionProbe(paneId, token: token, cycle: cycle) else { return }
                await self.refreshAgent(paneId, cycle: cycle)
            }
            await self?.detectionProbesFinished(paneId, token: token)
        }
        detectionProbes[paneId] = ScheduledTask(token: token, task: task)
    }

    private func needsSessionProbe(_ paneId: String, token: UUID, cycle: Int) -> Bool {
        guard cycle == generation, detectionProbes[paneId]?.token == token else { return false }
        return state.pane(paneId)?.agentSession == nil
    }

    private func detectionProbesFinished(_ paneId: String, token: UUID) {
        guard detectionProbes[paneId]?.token == token else { return }
        detectionProbes[paneId] = nil
    }

    private func needsSessionStartProbe(_ paneId: String, expecting sessionId: String, token: UUID, cycle: Int) -> Bool {
        guard cycle == generation, sessionProbes[paneId]?.token == token else { return false }
        guard state.pane(paneId)?.sessionId != sessionId else {
            sessionProbes[paneId] = nil
            return false
        }
        return true
    }

    private func sessionProbesFinished(_ paneId: String, token: UUID) {
        guard sessionProbes[paneId]?.token == token else { return }
        sessionProbes[paneId] = nil
    }

    private func updateReconciliation() {
        let needed = available
            && (!openChats.isEmpty
                || state.panes.contains { $0.agent != nil && ($0.agentStatus == .working || $0.agentStatus == .blocked) })
        guard needed else {
            reconciliation?.cancel()
            reconciliation = nil
            return
        }
        guard reconciliation == nil else { return }
        let cycle = generation
        let interval = configuration.reconciliationInterval
        reconciliation = Task { [weak self] in
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: interval)) != nil, let self else { return }
                await self.reconcileSessions(cycle: cycle)
            }
        }
    }

    private func reconcileSessions(cycle: Int) async {
        guard cycle == generation else { return }
        do {
            let agents = try await client.agentList()
            guard cycle == generation else { return }
            var changed = false
            for agent in agents {
                guard let session = agent.agentSession, let pane = state.pane(agent.paneId), pane.agentSession != session else { continue }
                state.updatePane(agent.paneId) { $0.agentSession = session }
                hub.publish(.sessionChanged(agent.paneId, sessionId: session.value))
                changed = true
            }
            if changed {
                scheduleTreeRefresh()
            }
        } catch {
            handleRequestFailure(error)
        }
    }
}
