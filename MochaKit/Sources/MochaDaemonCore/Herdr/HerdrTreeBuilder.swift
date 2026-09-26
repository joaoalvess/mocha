import MochaHerdr
import MochaProtocol

struct HerdrGitSnapshot: Sendable, Equatable {
    var branches: [String: String] = [:]
    var dirtyDirectories: Set<String> = []
}

enum HerdrTreeBuilder {
    static let defaultAgentTitle = "Claude Code"

    static func workspaceDirectory(_ workspace: HerdrWorkspace, in state: HerdrState) -> String? {
        if let checkoutPath = workspace.worktree?.checkoutPath {
            return checkoutPath
        }
        guard let activeTabId = workspace.activeTabId else { return nil }
        return state.panes.first { $0.tabId == activeTabId }?.cwd
    }

    static func agentDirectory(_ pane: HerdrPane) -> String? {
        pane.foregroundCwd ?? pane.cwd
    }

    static func workspaceDirectories(in state: HerdrState) -> Set<String> {
        Set(state.workspaces.compactMap { workspaceDirectory($0, in: state) })
    }

    static func agentDirectories(in state: HerdrState) -> Set<String> {
        Set(state.panes.filter { $0.agent != nil }.compactMap(agentDirectory))
    }

    static func build(state: HerdrState, git: HerdrGitSnapshot) -> [WorkspaceNode] {
        let ordered = state.workspaces.enumerated()
            .sorted { ($0.element.number, $0.offset) < ($1.element.number, $1.offset) }
            .map(\.element)
        var nodes: [String: WorkspaceNode] = [:]
        for workspace in ordered {
            nodes[workspace.workspaceId] = node(for: workspace, state: state, git: git)
        }
        var parents: [String: String] = [:]
        for workspace in ordered where workspace.worktree?.isLinkedWorktree == true {
            let parent = ordered.first { candidate in
                candidate.worktree?.isLinkedWorktree == false && candidate.worktree?.repoKey == workspace.worktree?.repoKey
            }
            if let parent {
                parents[workspace.workspaceId] = parent.workspaceId
            }
        }
        var roots: [WorkspaceNode] = []
        for workspace in ordered where parents[workspace.workspaceId] == nil {
            guard var root = nodes[workspace.workspaceId] else { continue }
            root.children = ordered
                .filter { parents[$0.workspaceId] == workspace.workspaceId }
                .compactMap { nodes[$0.workspaceId] }
            roots.append(root)
        }
        return roots
    }

    static func aggregateStatus(_ statuses: [AgentStatus]) -> AgentStatus {
        let priority: [AgentStatus] = [.blocked, .working, .done, .idle]
        return priority.first { statuses.contains($0) } ?? .unknown
    }

    static func agentStatus(_ status: HerdrAgentStatus) -> AgentStatus {
        AgentStatus(rawValue: status.rawValue) ?? .unknown
    }

    private static func node(for workspace: HerdrWorkspace, state: HerdrState, git: HerdrGitSnapshot) -> WorkspaceNode {
        let directory = workspaceDirectory(workspace, in: state)
        let tabs = state.tabs
            .filter { $0.workspaceId == workspace.workspaceId }
            .map { tab in
                TabNode(
                    id: tab.tabId,
                    title: tab.label,
                    agents: state.panes
                        .filter { $0.tabId == tab.tabId && $0.agent != nil }
                        .map { agentSummary($0, tab: tab, workspace: workspace, git: git) }
                )
            }
        return WorkspaceNode(
            id: workspace.workspaceId,
            label: workspace.label,
            number: workspace.number,
            repoName: workspace.worktree?.repoName,
            branch: directory.flatMap { git.branches[$0] },
            isDirty: directory.map { git.dirtyDirectories.contains($0) } ?? false,
            agentStatus: aggregateStatus(tabs.flatMap { $0.agents.map(\.status) }),
            tabs: tabs
        )
    }

    private static func agentSummary(_ pane: HerdrPane, tab: HerdrTab, workspace: HerdrWorkspace, git: HerdrGitSnapshot) -> AgentSummary {
        AgentSummary(
            id: pane.paneId,
            kind: pane.agent ?? "",
            status: agentStatus(pane.agentStatus),
            title: title(of: pane, tabLabel: tab.label),
            workspaceLabel: workspace.label,
            branch: agentDirectory(pane).flatMap { git.branches[$0] },
            sessionId: pane.sessionId
        )
    }

    private static func title(of pane: HerdrPane, tabLabel: String) -> String {
        if let title = pane.terminalTitleStripped, !title.isEmpty {
            return title
        }
        if !tabLabel.isEmpty {
            return tabLabel
        }
        return defaultAgentTitle
    }
}
