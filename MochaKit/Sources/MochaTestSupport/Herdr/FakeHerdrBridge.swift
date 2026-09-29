import Foundation
import MochaDaemonCore
import MochaProtocol
import Synchronization

public struct FakeHerdrPromptCall: Sendable, Equatable {
    public let agentId: AgentID
    public let text: String

    public init(agentId: AgentID, text: String) {
        self.agentId = agentId
        self.text = text
    }
}

public struct FakeHerdrSessionRefresh: Sendable, Equatable {
    public let agentId: AgentID
    public let sessionId: String

    public init(agentId: AgentID, sessionId: String) {
        self.agentId = agentId
        self.sessionId = sessionId
    }
}

public enum FakeHerdrControlCall: Sendable, Equatable {
    case model(AgentID, ModelAlias)
    case effort(AgentID, EffortLevel)
    case mode(AgentID, PermissionModeTarget)
}

public final class FakeHerdrBridge: HerdrBridging {
    private struct State {
        var agents: [AgentID: HerdrAgent]
        var movedPanes: [AgentID: AgentID] = [:]
        var serverInfo: HerdrServerInfo?
        var workspaceRoots: [WorkspaceRoot] = []
        var promptError: HerdrBridgeError?
        var interruptError: HerdrBridgeError?
        var promptCalls: [FakeHerdrPromptCall] = []
        var interruptCalls: [AgentID] = []
        var openChatsCalls: [Set<AgentID>] = []
        var resolveCalls: [AgentID] = []
        var sessionRefreshCalls: [FakeHerdrSessionRefresh] = []
        var dirtyRefreshCalls: [AgentID] = []
        var newAgentTabCalls: [WorkspaceID] = []
        var newAgentTabError: HerdrBridgeError?
        var controlCalls: [FakeHerdrControlCall] = []
        var controlError: HerdrBridgeError?
        var modeResult: String?
        var currentModes: [AgentID: String] = [:]
        var holdsNewAgentTabs = false
        var heldNewAgentTabs: [CheckedContinuation<Void, Never>] = []
    }

    public static let defaultServerInfo = HerdrServerInfo(version: "0.9.1", protocolVersion: 22)

    private let hub: HerdrBridgeEventHub
    private let state: Mutex<State>

    public init(
        tree: [WorkspaceNode] = [],
        agents: [HerdrAgent] = [],
        available: Bool = true,
        serverInfo: HerdrServerInfo? = FakeHerdrBridge.defaultServerInfo
    ) {
        hub = HerdrBridgeEventHub(tree: tree, available: available)
        state = Mutex(
            State(
                agents: Dictionary(agents.map { ($0.paneId, $0) }, uniquingKeysWith: { _, last in last }),
                serverInfo: serverInfo
            )
        )
    }

    public func events() -> AsyncStream<HerdrBridgeEvent> {
        hub.subscribe()
    }

    public var isAvailable: Bool {
        get async { hub.isAvailable }
    }

    public func tree() async -> [WorkspaceNode] {
        hub.tree
    }

    public func agent(_ id: AgentID) async -> HerdrAgent? {
        state.withLock { $0.agents[id] }
    }

    public func resolve(_ id: AgentID) async -> AgentID {
        state.withLock { state in
            state.resolveCalls.append(id)
            var current = id
            var visited: Set<AgentID> = [id]
            while let next = state.movedPanes[current], visited.insert(next).inserted {
                current = next
            }
            return current
        }
    }

    public func prompt(_ id: AgentID, text: String) async throws {
        let error = state.withLock { state in
            state.promptCalls.append(FakeHerdrPromptCall(agentId: id, text: text))
            return state.promptError
        }
        try failIfNeeded(error)
    }

    public func interrupt(_ id: AgentID) async throws {
        let error = state.withLock { state in
            state.interruptCalls.append(id)
            return state.interruptError
        }
        try failIfNeeded(error)
    }

    public func setModel(_ id: AgentID, model: ModelAlias) async throws {
        try failIfNeeded(state.withLock { state in
            state.controlCalls.append(.model(id, model))
            return state.controlError
        })
    }

    public func setEffort(_ id: AgentID, level: EffortLevel) async throws {
        try failIfNeeded(state.withLock { state in
            state.controlCalls.append(.effort(id, level))
            return state.controlError
        })
    }

    public func setMode(_ id: AgentID, mode: PermissionModeTarget) async throws -> String {
        let (error, result) = state.withLock { state in
            state.controlCalls.append(.mode(id, mode))
            return (state.controlError, state.modeResult ?? mode.rawValue)
        }
        try failIfNeeded(error)
        state.withLock { $0.currentModes[id] = result }
        return result
    }

    public func currentMode(_ id: AgentID) async -> String? {
        state.withLock { $0.currentModes[id] }
    }

    public func setControlError(_ error: HerdrBridgeError?) {
        state.withLock { $0.controlError = error }
    }

    public func setModeResult(_ mode: String?) {
        state.withLock { $0.modeResult = mode }
    }

    public func setCurrentMode(_ mode: String?, of id: AgentID) {
        state.withLock { $0.currentModes[id] = mode }
    }

    public var controlCalls: [FakeHerdrControlCall] {
        state.withLock { $0.controlCalls }
    }

    public func setOpenChats(_ ids: Set<AgentID>) async {
        state.withLock { $0.openChatsCalls.append(ids) }
    }

    public var serverInfo: HerdrServerInfo? {
        get async { state.withLock { $0.serverInfo } }
    }

    public func workspaceRoots() async -> [WorkspaceRoot] {
        state.withLock { $0.workspaceRoots }
    }

    public func refreshAgent(_ id: AgentID, expectingSession sessionId: String) async {
        let changed = state.withLock { state -> Bool in
            state.sessionRefreshCalls.append(FakeHerdrSessionRefresh(agentId: id, sessionId: sessionId))
            guard var agent = state.agents[id], agent.sessionId != sessionId else { return false }
            agent.sessionId = sessionId
            state.agents[id] = agent
            return true
        }
        if changed {
            hub.publish(.sessionChanged(id, sessionId: sessionId))
        }
    }

    public func refreshDirtyState(ofAgent id: AgentID) async {
        state.withLock { $0.dirtyRefreshCalls.append(id) }
    }

    public func newAgentTab(in workspaceId: WorkspaceID) async throws -> AgentID {
        let error = state.withLock { state in
            state.newAgentTabCalls.append(workspaceId)
            return state.newAgentTabError
        }
        await waitForNewAgentTabRelease()
        try failIfNeeded(error)
        return state.withLock { state in
            var number = 1
            while state.agents["\(workspaceId):p\(number)"] != nil {
                number += 1
            }
            let agentId = "\(workspaceId):p\(number)"
            state.agents[agentId] = HerdrAgent(paneId: agentId, workspaceId: workspaceId, kind: "claude", status: .idle)
            return agentId
        }
    }

    public func setNewAgentTabError(_ error: HerdrBridgeError?) {
        state.withLock { $0.newAgentTabError = error }
    }

    public func holdNewAgentTabs() {
        state.withLock { $0.holdsNewAgentTabs = true }
    }

    public func releaseNewAgentTabs() {
        let held = state.withLock { state in
            state.holdsNewAgentTabs = false
            defer { state.heldNewAgentTabs.removeAll() }
            return state.heldNewAgentTabs
        }
        for continuation in held {
            continuation.resume()
        }
    }

    public var newAgentTabCalls: [WorkspaceID] {
        state.withLock { $0.newAgentTabCalls }
    }

    public var heldNewAgentTabCount: Int {
        state.withLock { $0.heldNewAgentTabs.count }
    }

    public func setTree(_ tree: [WorkspaceNode]) {
        hub.publish(.treeChanged(tree))
    }

    public func setAvailable(_ available: Bool) {
        guard hub.isAvailable != available else { return }
        hub.publish(.availability(available))
    }

    public func emit(_ event: HerdrBridgeEvent) {
        hub.publish(event)
    }

    public func setAgent(_ agent: HerdrAgent) {
        state.withLock { $0.agents[agent.paneId] = agent }
    }

    public func removeAgent(_ id: AgentID) {
        _ = state.withLock { $0.agents.removeValue(forKey: id) }
    }

    public func movePane(from oldId: AgentID, to newId: AgentID) {
        state.withLock { state in
            for (key, value) in state.movedPanes where value == oldId {
                state.movedPanes[key] = newId
            }
            state.movedPanes[oldId] = newId
            if var agent = state.agents.removeValue(forKey: oldId) {
                agent.paneId = newId
                state.agents[newId] = agent
            }
        }
        hub.publish(.paneMoved(from: oldId, to: newId))
    }

    public func setPromptError(_ error: HerdrBridgeError?) {
        state.withLock { $0.promptError = error }
    }

    public func setInterruptError(_ error: HerdrBridgeError?) {
        state.withLock { $0.interruptError = error }
    }

    public func setServerInfo(_ info: HerdrServerInfo?) {
        state.withLock { $0.serverInfo = info }
    }

    public func setWorkspaceRoots(_ roots: [WorkspaceRoot]) {
        state.withLock { $0.workspaceRoots = roots }
    }

    public func finishEvents() {
        hub.finish()
    }

    public var promptCalls: [FakeHerdrPromptCall] {
        state.withLock { $0.promptCalls }
    }

    public var interruptCalls: [AgentID] {
        state.withLock { $0.interruptCalls }
    }

    public var openChatsCalls: [Set<AgentID>] {
        state.withLock { $0.openChatsCalls }
    }

    public var resolveCalls: [AgentID] {
        state.withLock { $0.resolveCalls }
    }

    public var sessionRefreshCalls: [FakeHerdrSessionRefresh] {
        state.withLock { $0.sessionRefreshCalls }
    }

    public var dirtyRefreshCalls: [AgentID] {
        state.withLock { $0.dirtyRefreshCalls }
    }

    public var subscriberCount: Int {
        hub.subscriberCount
    }

    private func waitForNewAgentTabRelease() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld = state.withLock { state in
                guard state.holdsNewAgentTabs else { return false }
                state.heldNewAgentTabs.append(continuation)
                return true
            }
            if !isHeld {
                continuation.resume()
            }
        }
    }

    private func failIfNeeded(_ configured: HerdrBridgeError?) throws {
        guard hub.isAvailable else { throw HerdrBridgeError.unavailable }
        if let configured {
            throw configured
        }
    }
}
