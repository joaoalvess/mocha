import MochaHerdr
import MochaProtocol

public protocol HerdrBridging: Sendable {
    func events() -> AsyncStream<HerdrBridgeEvent>
    var isAvailable: Bool { get async }
    func tree() async -> [WorkspaceNode]
    func agent(_ id: AgentID) async -> HerdrAgent?
    func resolve(_ id: AgentID) async -> AgentID
    func prompt(_ id: AgentID, text: String) async throws
    func interrupt(_ id: AgentID) async throws
    func closeAgent(_ id: AgentID) async throws
    func setModel(_ id: AgentID, model: ModelAlias) async throws
    func setEffort(_ id: AgentID, level: EffortLevel) async throws
    func setMode(_ id: AgentID, mode: PermissionModeTarget) async throws -> String
    func currentMode(_ id: AgentID) async -> String?
    func setOpenChats(_ ids: Set<AgentID>) async
    func refreshAgent(_ id: AgentID, expectingSession sessionId: String) async
    func refreshDirtyState(ofAgent id: AgentID) async
    func newAgentTab(in workspaceId: WorkspaceID) async throws -> AgentID
    func newCodexTab(in workspaceId: WorkspaceID, remote: String) async throws -> (paneId: AgentID, cwd: String?)
    var serverInfo: HerdrServerInfo? { get async }
    func workspaceRoots() async -> [WorkspaceRoot]
    func splitPane(_ id: AgentID) async throws -> (paneId: AgentID, cwd: String?)
    func startCodexAgent(in paneId: AgentID, directory: String?, remote: String, extraArguments: [String]) async throws
    func closePane(_ id: AgentID) async throws
}

extension HerdrBridging {
    public func newCodexTab(in workspaceId: WorkspaceID, remote: String) async throws -> (paneId: AgentID, cwd: String?) {
        throw HerdrBridgeError.unavailable
    }

    public func workspaceRoots() async -> [WorkspaceRoot] {
        []
    }

    public func splitPane(_ id: AgentID) async throws -> (paneId: AgentID, cwd: String?) {
        throw HerdrBridgeError.unavailable
    }

    public func startCodexAgent(in paneId: AgentID, directory: String?, remote: String, extraArguments: [String]) async throws {
        throw HerdrBridgeError.unavailable
    }

    public func closePane(_ id: AgentID) async throws {
        throw HerdrBridgeError.unavailable
    }
}

public struct HerdrServerInfo: Sendable, Equatable {
    public var version: String
    public var protocolVersion: Int

    public init(version: String, protocolVersion: Int) {
        self.version = version
        self.protocolVersion = protocolVersion
    }

    public var isSupportedProtocol: Bool {
        protocolVersion == HerdrProtocol.supportedVersion
    }

    public var protocolWarning: String? {
        guard !isSupportedProtocol else { return nil }
        return "Herdr \(version) usa o protocolo \(protocolVersion); o Mocha espera o \(HerdrProtocol.supportedVersion). Funcionando em melhor esforço."
    }
}

public enum HerdrBridgeEvent: Sendable, Equatable {
    case snapshot(tree: [WorkspaceNode], available: Bool)
    case treeChanged([WorkspaceNode])
    case agentStatus(AgentID, AgentStatus, title: String?)
    case sessionChanged(AgentID, sessionId: String?)
    case availability(Bool)
    case paneMoved(from: AgentID, to: AgentID)
}

public struct HerdrAgent: Sendable, Equatable {
    public var paneId: AgentID
    public var workspaceId: WorkspaceID
    public var kind: String
    public var status: AgentStatus
    public var sessionId: String?
    public var cwd: String?
    public var foregroundCwd: String?
    public var terminalTitle: String?

    public init(
        paneId: AgentID,
        workspaceId: WorkspaceID,
        kind: String,
        status: AgentStatus,
        sessionId: String? = nil,
        cwd: String? = nil,
        foregroundCwd: String? = nil,
        terminalTitle: String? = nil
    ) {
        self.paneId = paneId
        self.workspaceId = workspaceId
        self.kind = kind
        self.status = status
        self.sessionId = sessionId
        self.cwd = cwd
        self.foregroundCwd = foregroundCwd
        self.terminalTitle = terminalTitle
    }
}

public enum HerdrBridgeError: Error, Sendable, Equatable {
    case unavailable
    case agentNotFound
    case agentBlocked
    case workspaceNotFound
    case modeUnavailable
    case screenBusy
    case herdr(code: String, message: String)
}
