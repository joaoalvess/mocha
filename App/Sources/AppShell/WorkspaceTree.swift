import MochaProtocol

extension WorkspaceNode {
    var allAgents: [AgentSummary] {
        tabs.flatMap(\.agents) + children.flatMap(\.allAgents)
    }
}

extension [WorkspaceNode] {
    var allAgents: [AgentSummary] {
        flatMap(\.allAgents)
    }

    func agent(withId id: AgentID) -> AgentSummary? {
        allAgents.first { $0.id == id }
    }

    func agent(withSessionId sessionId: String) -> AgentSummary? {
        allAgents.first { $0.sessionId == sessionId }
    }

    mutating func updateAgent(withId id: AgentID, _ update: (inout AgentSummary) -> Void) {
        for index in indices {
            self[index].updateAgent(withId: id, update)
        }
    }
}

extension WorkspaceNode {
    mutating func updateAgent(withId id: AgentID, _ update: (inout AgentSummary) -> Void) {
        for tabIndex in tabs.indices {
            for agentIndex in tabs[tabIndex].agents.indices where tabs[tabIndex].agents[agentIndex].id == id {
                update(&tabs[tabIndex].agents[agentIndex])
            }
        }
        children.updateAgent(withId: id, update)
    }
}
