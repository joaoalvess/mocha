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

    @Test func activeKeepsOnlyNeedsYouAndWorking() {
        let sections = HomeSections.make(
            agents: [
                agent("a", status: .blocked),
                agent("b", status: .working),
                agent("c", status: .idle),
                agent("d", status: .idle, lastActivityAgo: 3_600),
            ],
            archived: [archived("e", endedAgo: 7_200)],
            now: now
        )

        #expect(StartSections.active(sections).map(\.kind) == [.needsYou, .working])
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
