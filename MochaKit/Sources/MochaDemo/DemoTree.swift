import MochaProtocol

extension AgentStatus {
    var attentionRank: Int {
        switch self {
        case .blocked: 4
        case .working: 3
        case .done: 2
        case .idle: 1
        case .unknown: 0
        }
    }
}

extension WorkspaceNode {
    var aggregatedAgentStatus: AgentStatus {
        tabs.flatMap(\.agents).map(\.status).max { $0.attentionRank < $1.attentionRank } ?? .unknown
    }

    mutating func updateAgent(withId id: AgentID, _ update: (inout AgentSummary) -> Void) -> Bool {
        for tabIndex in tabs.indices {
            guard let agentIndex = tabs[tabIndex].agents.firstIndex(where: { $0.id == id }) else { continue }
            update(&tabs[tabIndex].agents[agentIndex])
            agentStatus = aggregatedAgentStatus
            return true
        }
        return children.updateAgent(withId: id, update)
    }

    func withoutSupportedAgents() -> WorkspaceNode {
        var workspace = self
        workspace.tabs = tabs.map { tab in
            let others = tab.agents.filter { $0.kind != "claude" && $0.kind != "codex" }
            guard others.count != tab.agents.count else { return tab }
            return TabNode(id: tab.id, title: others.first?.title ?? DemoTree.shellTitle, agents: others)
        }
        workspace.children = children.map { $0.withoutSupportedAgents() }
        workspace.agentStatus = workspace.aggregatedAgentStatus
        return workspace
    }
}

enum DemoTree {
    static let shellTitle = "zsh"
}

extension [WorkspaceNode] {
    func agent(withId id: AgentID) -> AgentSummary? {
        for workspace in self {
            if let agent = workspace.tabs.lazy.flatMap(\.agents).first(where: { $0.id == id }) {
                return agent
            }
            if let agent = workspace.children.agent(withId: id) {
                return agent
            }
        }
        return nil
    }

    func workspace(withId id: WorkspaceID) -> WorkspaceNode? {
        for workspace in self {
            if workspace.id == id {
                return workspace
            }
            if let child = workspace.children.workspace(withId: id) {
                return child
            }
        }
        return nil
    }

    func agent(withSessionId sessionId: String) -> AgentSummary? {
        allAgents.first { $0.sessionId == sessionId }
    }

    var allAgents: [AgentSummary] {
        flatMap { $0.tabs.flatMap(\.agents) + $0.children.allAgents }
    }

    @discardableResult
    mutating func updateAgent(withId id: AgentID, _ update: (inout AgentSummary) -> Void) -> Bool {
        for index in indices {
            if self[index].updateAgent(withId: id, update) {
                return true
            }
        }
        return false
    }

    @discardableResult
    mutating func updateWorkspace(withId id: WorkspaceID, _ update: (inout WorkspaceNode) -> Void) -> Bool {
        for index in indices {
            if self[index].id == id {
                update(&self[index])
                return true
            }
            if self[index].children.updateWorkspace(withId: id, update) {
                return true
            }
        }
        return false
    }
}
