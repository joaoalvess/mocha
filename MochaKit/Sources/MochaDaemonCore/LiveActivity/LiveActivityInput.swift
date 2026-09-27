import MochaProtocol

public struct LiveActivityInput: Sendable, Equatable {
    public var agents: [AgentSummary]
    public var pending: [PendingRequest]
    public var foregroundDevices: Set<DeviceID>
    public var tabTitles: [AgentID: String]

    public init(
        agents: [AgentSummary],
        pending: [PendingRequest] = [],
        foregroundDevices: Set<DeviceID> = [],
        tabTitles: [AgentID: String] = [:]
    ) {
        self.agents = agents
        self.pending = pending
        self.foregroundDevices = foregroundDevices
        self.tabTitles = tabTitles
    }

    static func tabTitles(in tree: [WorkspaceNode]) -> [AgentID: String] {
        var titles: [AgentID: String] = [:]
        for workspace in tree {
            for tab in workspace.tabs {
                for agent in tab.agents where titles[agent.id] == nil {
                    titles[agent.id] = tab.title
                }
            }
            titles.merge(tabTitles(in: workspace.children)) { current, _ in current }
        }
        return titles
    }
}
