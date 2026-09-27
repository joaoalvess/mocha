import MochaProtocol

public struct LiveActivityInput: Sendable, Equatable {
    public var agents: [AgentSummary]
    public var foregroundDevices: Set<DeviceID>

    public init(agents: [AgentSummary], foregroundDevices: Set<DeviceID> = []) {
        self.agents = agents
        self.foregroundDevices = foregroundDevices
    }
}
