import Foundation
import MochaProtocol

public actor ModelSwitchGate {
    public static let window: TimeInterval = 5

    private let now: @Sendable () -> Date
    private var pending: [AgentID: Date] = [:]

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func begin(_ agentId: AgentID) {
        pending[agentId] = now()
    }

    public func end(_ agentId: AgentID) {
        pending[agentId] = nil
    }

    public func approves(_ agentId: AgentID, at date: Date) -> Bool {
        guard let started = pending[agentId] else { return false }
        let elapsed = date.timeIntervalSince(started)
        return elapsed >= 0 && elapsed <= Self.window
    }
}
