import MochaProtocol

extension WorkspaceNode {
    public var allAgents: [AgentSummary] {
        tabs.flatMap(\.agents) + children.flatMap(\.allAgents)
    }

    mutating func updateAgent(withId id: AgentID, _ update: (inout AgentSummary) -> Void) {
        for tabIndex in tabs.indices {
            for agentIndex in tabs[tabIndex].agents.indices where tabs[tabIndex].agents[agentIndex].id == id {
                update(&tabs[tabIndex].agents[agentIndex])
            }
        }
        children.updateAgent(withId: id, update)
    }
}

extension [WorkspaceNode] {
    public var allAgents: [AgentSummary] {
        flatMap(\.allAgents)
    }

    public var flattenedWorkspaces: [WorkspaceNode] {
        flatMap { [$0] + $0.children.flattenedWorkspaces }
    }

    public func workspaceNode(containingAgent id: AgentID) -> WorkspaceNode? {
        for workspace in self {
            if let child = workspace.children.workspaceNode(containingAgent: id) {
                return child
            }
            if workspace.tabs.contains(where: { $0.agents.contains { $0.id == id } }) {
                return workspace
            }
        }
        return nil
    }

    public func agent(withId id: AgentID) -> AgentSummary? {
        allAgents.first { $0.id == id }
    }

    public func agent(withSessionId sessionId: String) -> AgentSummary? {
        allAgents.first { $0.sessionId == sessionId }
    }

    public func tab(containingAgent id: AgentID) -> TabNode? {
        for workspace in self {
            if let tab = workspace.tabs.first(where: { $0.agents.contains { $0.id == id } }) {
                return tab
            }
            if let tab = workspace.children.tab(containingAgent: id) {
                return tab
            }
        }
        return nil
    }

    public mutating func updateAgent(withId id: AgentID, _ update: (inout AgentSummary) -> Void) {
        for index in indices {
            self[index].updateAgent(withId: id, update)
        }
    }
}
