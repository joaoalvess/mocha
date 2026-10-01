import MochaProtocol

public struct LiveActivityInput: Sendable, Equatable {
    public var agents: [AgentSummary]
    public var pending: [PendingRequest]
    public var foregroundDevices: Set<DeviceID>
    public var foregroundAgents: [DeviceID: AgentID]
    public var prompts: [AgentID: String]
    public var decisions: [AgentID: PendingDecision]
    public var herdrStatuses: [AgentID: AgentStatus]

    public init(
        agents: [AgentSummary],
        pending: [PendingRequest] = [],
        foregroundDevices: Set<DeviceID> = [],
        foregroundAgents: [DeviceID: AgentID] = [:],
        prompts: [AgentID: String] = [:],
        decisions: [AgentID: PendingDecision] = [:],
        herdrStatuses: [AgentID: AgentStatus] = [:]
    ) {
        self.agents = agents
        self.pending = pending
        self.foregroundDevices = foregroundDevices
        self.foregroundAgents = foregroundAgents
        self.prompts = prompts
        self.decisions = decisions
        self.herdrStatuses = herdrStatuses
    }
}
