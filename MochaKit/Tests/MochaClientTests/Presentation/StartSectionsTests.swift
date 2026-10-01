import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct StartSectionsTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func agent(
        _ id: AgentID,
        kind: String = "claude",
        status: AgentStatus = .idle,
        lastActivityAgo: TimeInterval = 60,
        preview: MessagePreview? = MessagePreview(author: .assistant, text: "Pronto."),
        activity: ToolActivity? = nil
    ) -> AgentSummary {
        AgentSummary(
            id: id,
            kind: kind,
            status: status,
            title: id,
            workspaceLabel: "ws-" + id,
            sessionId: "s-" + id,
            lastActivityAt: now.addingTimeInterval(-lastActivityAgo),
            preview: preview,
            activity: activity
        )
    }

    private func archived(_ id: String, endedAgo: TimeInterval) -> ArchivedSession {
        ArchivedSession(
            id: id,
            agentId: "w9:p1",
            title: id,
            workspaceLabel: "ws-" + id,
            preview: MessagePreview(author: .user, text: "revisa o README"),
            reason: .ended,
            endedAt: now.addingTimeInterval(-endedAgo)
        )
    }

    @Test func openListsEveryLiveAgentWithAttentionFirstThenByActivity() {
        let cards = StartSections.open(
            agents: [
                agent("idle-old", status: .idle, lastActivityAgo: 3_600),
                agent("working", status: .working, lastActivityAgo: 600),
                agent("idle-new", status: .idle, lastActivityAgo: 30),
                agent("blocked", status: .blocked, lastActivityAgo: 900),
                agent("codex", kind: "codex", status: .done, lastActivityAgo: 120),
                agent("shell", kind: "shell", status: .idle),
            ],
            now: now
        )

        #expect(cards.map(\.target) == [
            .agent("blocked"), .agent("working"), .agent("idle-new"), .agent("codex"), .agent("idle-old"),
        ])
        #expect(cards.last?.state == .archived)
    }

    @Test func recentsAreSortedByActivityAndIncludeArchivedSessions() {
        let items = StartSections.recents(
            agents: [agent("old", lastActivityAgo: 600), agent("new", status: .working, lastActivityAgo: 5)],
            archived: [archived("gone", endedAgo: 300)],
            now: now
        )

        #expect(items.map(\.card.target) == [.agent("new"), .session("gone"), .agent("old")])
        #expect(items.map(\.stateText) == ["Trabalhando", "Arquivado", "Arquivado"])
    }

    @Test func recentsRespectTheLimitAndSkipOtherAgents() {
        let agents = (0..<14).map { agent("a\($0)", lastActivityAgo: TimeInterval($0 + 1)) } + [agent("x", kind: "gemini", lastActivityAgo: 0)]

        let items = StartSections.recents(agents: agents, archived: [], now: now)

        #expect(items.count == StartSections.recentLimit)
        #expect(items.first?.card.target == .agent("a0"))
    }

    @Test func thumbnailSplitsPreviewByAuthorAndNamesTheTool() {
        let items = StartSections.recents(
            agents: [
                agent("u", lastActivityAgo: 1, preview: MessagePreview(author: .user, text: "troca o tema"), activity: ToolActivity(toolName: "Bash", summary: "npm run build", status: .running)),
                agent("c", kind: "codex", lastActivityAgo: 2, preview: nil),
            ],
            archived: [],
            now: now
        )

        #expect(items[0].thumbnail == RecentThumbnail(userText: "troca o tema", toolName: "Shell", toolSummary: "npm run build"))
        #expect(items[1].thumbnail == RecentThumbnail())
        #expect(items[1].card.provider == .codex)
    }
}
