import MochaProtocol

public enum ChatTargetChange: Sendable, Equatable {
    case unchanged
    case learnedSession(String)
    case sessionSwitched(String)
    case agentMoved(AgentID)
}

public enum ChatTargetTracking {
    public static func change(
        for target: ChatTarget,
        knownSessionId: String?,
        in workspaces: [WorkspaceNode]
    ) -> ChatTargetChange {
        guard case .agent(let agentId) = target else { return .unchanged }
        if let agent = workspaces.agent(withId: agentId) {
            guard let sessionId = agent.sessionId, sessionId != knownSessionId else { return .unchanged }
            return knownSessionId == nil ? .learnedSession(sessionId) : .sessionSwitched(sessionId)
        }
        guard let knownSessionId, let moved = workspaces.agent(withSessionId: knownSessionId) else { return .unchanged }
        return .agentMoved(moved.id)
    }

    public static func target(afterAck agentId: AgentID?, from target: ChatTarget) -> ChatTarget? {
        guard let agentId, case .agent(let current) = target, current != agentId else { return nil }
        return .agent(agentId)
    }
}
