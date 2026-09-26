import MochaProtocol

public struct ForegroundReporter: Sendable, Equatable {
    private struct Report: Sendable, Equatable {
        let agentId: AgentID?
        let isActive: Bool
    }

    private var lastSent: Report?

    public init() {}

    public mutating func message(agentId: AgentID?, isActive: Bool) -> ClientMessage? {
        let report = Report(agentId: agentId, isActive: isActive)
        guard report != lastSent else { return nil }
        lastSent = report
        return .setForeground(agentId: agentId, isActive: isActive)
    }

    public mutating func connectionClosed() {
        lastSent = nil
    }
}
