import Foundation
import MochaProtocol

public struct DrawerWorkspaceRow: Equatable, Sendable {
    public let id: WorkspaceID
    public let label: String
    public let branch: String?
    public let isDirty: Bool
    public let level: Int
    public let isExpanded: Bool
}

public struct DrawerShellRow: Equatable, Sendable {
    public let tabId: TabID
    public let title: String
    public let level: Int
}

public struct DrawerAgentRow: Sendable {
    public let agent: AgentSummary
    public let level: Int
    public let branch: String?

    public var isClaude: Bool {
        agent.kind == DrawerContent.claudeKind
    }

    public var isCodex: Bool {
        agent.kind == DrawerContent.codexKind
    }

    public var supportsChat: Bool {
        isClaude || isCodex
    }

    public var title: String {
        supportsChat ? agent.title : agent.kind
    }
}

public enum DrawerTreeRow: Identifiable, Sendable {
    case workspace(DrawerWorkspaceRow)
    case shell(DrawerShellRow)
    case agent(DrawerAgentRow)

    public var id: String {
        switch self {
        case .workspace(let row): "workspace:\(row.id)"
        case .shell(let row): "tab:\(row.tabId)"
        case .agent(let row): "agent:\(row.agent.id)"
        }
    }
}

public enum DrawerContent {
    public static let claudeKind = "claude"
    public static let codexKind = "codex"

    public static func treeRows(
        for workspaces: [WorkspaceNode],
        query: String,
        collapsed: Set<WorkspaceID>
    ) -> [DrawerTreeRow] {
        let needle = searchNeedle(query)
        var rows: [DrawerTreeRow] = []
        for workspace in workspaces {
            appendRows(for: workspace, level: 0, needle: needle, collapsed: collapsed, into: &rows)
        }
        return rows
    }

    public static func stateText(for status: AgentStatus) -> String? {
        switch status {
        case .working: "trabalhando"
        case .blocked: "precisa de você"
        case .idle, .done, .unknown: nil
        }
    }

    public static func searchNeedle(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func matches(_ text: String, needle: String) -> Bool {
        text.localizedStandardContains(needle)
    }

    public static func collapsedWorkspaces(from stored: String) -> Set<WorkspaceID> {
        Set(stored.split(separator: collapsedSeparator).map(String.init))
    }

    public static func storedValue(forCollapsed workspaces: Set<WorkspaceID>) -> String {
        workspaces.sorted().joined(separator: String(collapsedSeparator))
    }

    private static let collapsedSeparator: Character = "\n"

    private static func appendRows(
        for workspace: WorkspaceNode,
        level: Int,
        needle: String?,
        collapsed: Set<WorkspaceID>,
        into rows: inout [DrawerTreeRow]
    ) {
        guard let needle else {
            let isExpanded = !collapsed.contains(workspace.id)
            rows.append(.workspace(header(for: workspace, level: level, isExpanded: isExpanded)))
            guard isExpanded else { return }
            appendTabRows(for: workspace, level: level, needle: nil, into: &rows)
            for child in workspace.children {
                appendRows(for: child, level: level + 1, needle: nil, collapsed: collapsed, into: &rows)
            }
            return
        }
        if matches(workspace.label, needle: needle) {
            appendRows(for: workspace, level: level, needle: nil, collapsed: [], into: &rows)
            return
        }
        var nested: [DrawerTreeRow] = []
        appendTabRows(for: workspace, level: level, needle: needle, into: &nested)
        for child in workspace.children {
            appendRows(for: child, level: level + 1, needle: needle, collapsed: collapsed, into: &nested)
        }
        guard !nested.isEmpty else { return }
        rows.append(.workspace(header(for: workspace, level: level, isExpanded: true)))
        rows.append(contentsOf: nested)
    }

    private static func header(for workspace: WorkspaceNode, level: Int, isExpanded: Bool) -> DrawerWorkspaceRow {
        DrawerWorkspaceRow(
            id: workspace.id,
            label: workspace.label,
            branch: workspace.branch,
            isDirty: workspace.isDirty,
            level: level,
            isExpanded: isExpanded
        )
    }

    private static func appendTabRows(
        for workspace: WorkspaceNode,
        level: Int,
        needle: String?,
        into rows: inout [DrawerTreeRow]
    ) {
        for tab in workspace.tabs {
            let tabMatches = needle.map { matches(tab.title, needle: $0) } ?? true
            guard !tab.agents.isEmpty else {
                if tabMatches {
                    rows.append(.shell(DrawerShellRow(tabId: tab.id, title: tab.title, level: level)))
                }
                continue
            }
            for agent in tab.agents {
                let row = DrawerAgentRow(agent: agent, level: level, branch: displayedBranch(of: agent, in: workspace))
                if tabMatches || needle.map({ agentMatches(row, needle: $0) }) == true {
                    rows.append(.agent(row))
                }
            }
        }
    }

    private static func displayedBranch(of agent: AgentSummary, in workspace: WorkspaceNode) -> String? {
        guard let branch = agent.branch, branch != workspace.branch else { return nil }
        return branch
    }

    private static func agentMatches(_ row: DrawerAgentRow, needle: String) -> Bool {
        matches(row.agent.title, needle: needle) || matches(row.title, needle: needle)
            || matches(row.agent.kind, needle: needle)
    }
}
