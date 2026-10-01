import Foundation
import MochaProtocol

extension ArchivedSession {
    init(summary: AgentSummary, sessionId: String, reason: ArchiveReason, endedAt: Date) {
        self.init(
            id: sessionId,
            provider: AgentProvider(rawValue: summary.kind) ?? .claude,
            agentId: summary.id,
            title: summary.title,
            workspaceLabel: summary.workspaceLabel,
            model: summary.model,
            branch: summary.branch,
            preview: summary.preview,
            contextLeftPercent: summary.contextLeftPercent,
            reason: reason,
            endedAt: endedAt,
            sessionStartedAt: summary.sessionStartedAt,
            lastActivityAt: summary.lastActivityAt
        )
    }
}
