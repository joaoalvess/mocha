import MochaProtocol

public struct LiveActivityInput: Sendable, Equatable {
    public var agents: [AgentSummary]
    public var pending: [PendingRequest]
    public var foregroundDevices: Set<DeviceID>
    public var prompts: [AgentID: String]
    public var decisions: [AgentID: PendingDecision]

    public init(
        agents: [AgentSummary],
        pending: [PendingRequest] = [],
        foregroundDevices: Set<DeviceID> = [],
        prompts: [AgentID: String] = [:],
        decisions: [AgentID: PendingDecision] = [:]
    ) {
        self.agents = agents
        self.pending = pending
        self.foregroundDevices = foregroundDevices
        self.prompts = prompts
        self.decisions = decisions
    }
}
