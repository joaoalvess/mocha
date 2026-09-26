import Foundation
import MochaProtocol

struct DemoNewAgentTab {
    static let tabTitle = "Claude"
    static let agentTitle = "Claude Code"
    static let workspaceNotFoundMessage = "Workspace não encontrado"

    let tab: TabNode
    let chat: DemoChat

    var agentId: AgentID {
        chat.agentId
    }

    init(in workspace: WorkspaceNode, takenAgentIds: Set<AgentID>, now: Date) {
        let tabPrefix = "\(workspace.id):t"
        let panePrefix = "\(workspace.id):p"
        let highestTab = workspace.tabs.compactMap { Self.number(in: $0.id, after: tabPrefix) }.max() ?? 0
        let highestPane = takenAgentIds.compactMap { Self.number(in: $0, after: panePrefix) }.max() ?? 0
        let number = max(highestTab, highestPane) + 1
        let agent = AgentSummary(
            id: panePrefix + String(number),
            kind: "claude",
            status: .idle,
            title: Self.agentTitle,
            workspaceLabel: workspace.label,
            branch: workspace.branch,
            sessionId: UUID().uuidString.lowercased(),
            lastActivityAt: now
        )
        tab = TabNode(id: tabPrefix + String(number), title: Self.tabTitle, agents: [agent])
        chat = DemoChat(
            agentId: agent.id,
            meta: ChatMeta(title: agent.title, workspaceLabel: agent.workspaceLabel, branch: agent.branch, status: agent.status),
            items: []
        )
    }

    private static func number(in id: String, after prefix: String) -> Int? {
        guard id.hasPrefix(prefix) else { return nil }
        return Int(id.dropFirst(prefix.count))
    }
}
