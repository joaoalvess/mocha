import Foundation
import MochaProtocol
import MochaTranscript

enum TreeComposer {
    static let claudeKind = "claude"
    static let codexKind = "codex"

    static func compose(
        _ tree: [WorkspaceNode],
        metas: [String: TranscriptMeta],
        contexts: [String: Double] = [:],
        archivedAts: [String: Date] = [:],
        runningSubagents: [String: Int] = [:],
        pendingCounts: [AgentID: Int] = [:],
        controls: [AgentID: AgentControls] = [:]
    ) -> [WorkspaceNode] {
        mapAgents(tree) { agent in
            var agent = agent
            agent.pendingCount = pendingCounts[agent.id] ?? 0
            guard let sessionId = agent.sessionId else { return agent }
            return summary(
                agent,
                meta: metas[sessionId],
                contextUsedPercent: contexts[sessionId],
                archivedAt: archivedAts[sessionId],
                runningSubagents: runningSubagents[sessionId],
                controls: controls[agent.id]
            )
        }
    }

    static func summary(
        _ agent: AgentSummary,
        meta: TranscriptMeta?,
        contextUsedPercent: Double? = nil,
        archivedAt: Date? = nil,
        runningSubagents: Int? = nil,
        controls: AgentControls? = nil
    ) -> AgentSummary {
        var summary = agent
        if let runningSubagents, runningSubagents > 0 {
            summary.runningSubagents = runningSubagents
        }
        if let meta {
            if let title = meta.title, !title.isEmpty {
                summary.title = title
            }
            summary.model = meta.model
            summary.permissionMode = meta.permissionMode
            summary.lastActivityAt = meta.lastModified
            summary.preview = meta.preview
            summary.activity = meta.activity
            summary.contextLeftPercent = contextLeftPercent(meta)
            summary.contextUsedTokens = meta.contextTokens
            summary.sessionStartedAt = meta.sessionStartedAt
            summary.turnStartedAt = meta.turnStartedAt
            summary.turnEndedAt = meta.turnEndedAt
        }
        if let contextUsedPercent {
            summary.contextLeftPercent = contextLeftPercent(used: contextUsedPercent)
            summary.contextUsedTokens = Int((contextUsedPercent * Double(ContextWindow.size(forModel: summary.model ?? "")) / 100).rounded())
        }
        if let archivedAt {
            summary.archivedAt = archivedAt
        }
        if let controls, controls.sessionId == summary.sessionId {
            summary.permissionMode = controls.permissionMode(transcript: meta?.permissionMode)
            summary.model = controls.model(transcript: meta?.model)
            summary.effort = controls.effort(fallback: summary.effort)
        }
        return summary
    }

    static func contextLeftPercent(_ meta: TranscriptMeta) -> Int? {
        guard let tokens = meta.contextTokens else { return nil }
        let window = ContextWindow.size(forModel: meta.model ?? "")
        return contextLeftPercent(used: Double(tokens) * 100 / Double(window))
    }

    static func contextLeftPercent(used: Double) -> Int {
        Int(min(100, max(0, (100 - used).rounded())))
    }

    static func agentChatMeta(summary: AgentSummary?, meta: TranscriptMeta?, controls: AgentControls? = nil) -> ChatMeta {
        if let summary, summary.kind == codexKind {
            return codexChatMeta(summary)
        }
        let controls = controls.flatMap { $0.sessionId == summary?.sessionId ? $0 : nil }
        return ChatMeta(
            title: title(meta) ?? summary?.title ?? HerdrTreeBuilder.defaultAgentTitle,
            workspaceLabel: summary?.workspaceLabel ?? "",
            model: controls?.model(transcript: meta?.model) ?? meta?.model,
            branch: meta?.branch,
            status: summary?.status ?? .unknown,
            permissionMode: controls?.permissionMode(transcript: meta?.permissionMode) ?? meta?.permissionMode,
            effort: controls?.effort(fallback: nil)
        )
    }

    static func sessionChatMeta(meta: TranscriptMeta?, workspaceLabel: String) -> ChatMeta {
        ChatMeta(
            title: title(meta) ?? HerdrTreeBuilder.defaultAgentTitle,
            workspaceLabel: workspaceLabel,
            model: meta?.model,
            branch: meta?.branch,
            status: .unknown,
            permissionMode: meta?.permissionMode
        )
    }

    static func agents(in tree: [WorkspaceNode]) -> [AgentSummary] {
        tree.flatMap { workspace in
            workspace.tabs.flatMap(\.agents) + agents(in: workspace.children)
        }
    }

    static func agent(_ id: AgentID, in tree: [WorkspaceNode]) -> AgentSummary? {
        agents(in: tree).first { $0.id == id }
    }

    static func codexSummary(_ agent: AgentSummary, pane: CodexPaneState?, connected: Bool) -> AgentSummary {
        guard agent.kind == codexKind else { return agent }
        var agent = agent
        agent.controlAvailable = connected && pane != nil
        guard let pane else { return agent }
        let summary = pane.summary
        agent.sessionId = pane.threadId
        agent.status = pane.status
        if let title = summary.title {
            agent.title = title
        }
        agent.model = pane.settings.model ?? agent.model
        agent.effort = pane.settings.effort
        agent.permissionMode = pane.settings.mode
        agent.branch = summary.branch ?? agent.branch
        agent.lastActivityAt = summary.lastActivityAt ?? agent.lastActivityAt
        agent.preview = summary.preview
        agent.activity = summary.activity
        agent.contextLeftPercent = summary.contextLeftPercent
        agent.contextUsedTokens = summary.contextUsedTokens
        agent.sessionStartedAt = summary.sessionStartedAt
        agent.turnStartedAt = summary.turnStartedAt
        agent.turnEndedAt = summary.turnEndedAt
        return agent
    }

    static func codexChatMeta(_ summary: AgentSummary) -> ChatMeta {
        ChatMeta(
            title: summary.title,
            workspaceLabel: summary.workspaceLabel,
            model: summary.model,
            branch: summary.branch,
            status: summary.status,
            permissionMode: summary.permissionMode,
            effort: summary.effort
        )
    }

    static func codexOverlay(_ tree: [WorkspaceNode], panes: [AgentID: CodexPaneState], connected: Bool) -> [WorkspaceNode] {
        tree.map { workspace in
            var updated = workspace
            var touched = false
            updated.tabs = workspace.tabs.map { tab in
                var tab = tab
                tab.agents = tab.agents.map { agent in
                    guard agent.kind == codexKind else { return agent }
                    touched = true
                    return codexSummary(agent, pane: panes[agent.id], connected: connected)
                }
                return tab
            }
            if touched {
                updated.agentStatus = HerdrTreeBuilder.aggregateStatus(updated.tabs.flatMap { $0.agents.map(\.status) })
            }
            updated.children = codexOverlay(workspace.children, panes: panes, connected: connected)
            return updated
        }
    }

    static func containsWorkspace(_ id: WorkspaceID, in tree: [WorkspaceNode]) -> Bool {
        tree.contains { $0.id == id || containsWorkspace(id, in: $0.children) }
    }

    static func updatingAgent(
        _ id: AgentID,
        in tree: [WorkspaceNode],
        _ transform: (inout AgentSummary) -> Void
    ) -> [WorkspaceNode] {
        tree.map { workspace in
            var updated = workspace
            var touched = false
            updated.tabs = workspace.tabs.map { tab in
                var tab = tab
                tab.agents = tab.agents.map { agent in
                    guard agent.id == id else { return agent }
                    touched = true
                    var agent = agent
                    transform(&agent)
                    return agent
                }
                return tab
            }
            if touched {
                updated.agentStatus = HerdrTreeBuilder.aggregateStatus(updated.tabs.flatMap { $0.agents.map(\.status) })
            }
            updated.children = updatingAgent(id, in: workspace.children, transform)
            return updated
        }
    }

    private static func mapAgents(_ tree: [WorkspaceNode], _ transform: (AgentSummary) -> AgentSummary) -> [WorkspaceNode] {
        tree.map { workspace in
            var updated = workspace
            updated.tabs = workspace.tabs.map { tab in
                var tab = tab
                tab.agents = tab.agents.map(transform)
                return tab
            }
            updated.children = mapAgents(workspace.children, transform)
            return updated
        }
    }

    private static func title(_ meta: TranscriptMeta?) -> String? {
        guard let title = meta?.title, !title.isEmpty else { return nil }
        return title
    }
}
