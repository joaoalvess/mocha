import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct HomeSectionsTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    private func agent(
        _ id: AgentID,
        kind: String = "claude",
        status: AgentStatus = .idle,
        sessionId: String? = nil,
        lastActivityAgo: TimeInterval? = 60,
        preview: MessagePreview? = MessagePreview(author: .assistant, text: "Pronto."),
        activity: ToolActivity? = nil,
        sessionStartedAgo: TimeInterval? = nil,
        turnEndedAgo: TimeInterval? = nil,
        archivedAgo: TimeInterval? = nil
    ) -> AgentSummary {
        AgentSummary(
            id: id,
            kind: kind,
            status: status,
            title: id,
            workspaceLabel: "ws-" + id,
            sessionId: sessionId ?? "s-" + id,
            lastActivityAt: lastActivityAgo.map(ago),
            preview: preview,
            activity: activity,
            contextLeftPercent: 50,
            sessionStartedAt: sessionStartedAgo.map(ago),
            turnEndedAt: turnEndedAgo.map(ago),
            archivedAt: archivedAgo.map(ago)
        )
    }

    private func archived(_ id: String, endedAgo: TimeInterval, lastActivityAgo: TimeInterval? = nil) -> ArchivedSession {
        ArchivedSession(
            id: id,
            agentId: "w9:p1",
            title: id,
            workspaceLabel: "ws-" + id,
            preview: MessagePreview(author: .user, text: "revisa o README"),
            contextLeftPercent: 90,
            reason: .ended,
            endedAt: ago(endedAgo),
            lastActivityAt: lastActivityAgo.map(ago)
        )
    }

    private func kinds(_ sections: [HomeSection]) -> [HomeSectionKind] {
        sections.map(\.kind)
    }

    private func ids(_ sections: [HomeSection], _ kind: HomeSectionKind) -> [ChatTarget] {
        sections.first { $0.kind == kind }?.cards.map(\.target) ?? []
    }

    @Test func blockedTakesPrecedenceOverEverything() {
        let blocked = agent("a", status: .blocked, lastActivityAgo: 3_600, sessionStartedAgo: 30_000, archivedAgo: 10)
        #expect(HomeSections.kind(of: blocked, now: now) == .needsYou)
    }

    @Test func workingTakesPrecedenceOverArchived() {
        let working = agent("a", status: .working, lastActivityAgo: 3_600, sessionStartedAgo: 30_000, archivedAgo: 10)
        #expect(HomeSections.kind(of: working, now: now) == .working)
    }

    @Test(arguments: [AgentStatus.idle, .done, .unknown])
    func settledAgentsAreDoneOrArchived(status: AgentStatus) {
        #expect(HomeSections.kind(of: agent("a", status: status), now: now) == .done)
        #expect(HomeSections.kind(of: agent("a", status: status, archivedAgo: 5), now: now) == .archived)
    }

    @Test func archivedAtArchivesARecentAgent() {
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 5, archivedAgo: 1), now: now) == .archived)
    }

    @Test func tenMinutesAfterTheTurnArchives() {
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 1, turnEndedAgo: 599), now: now) == .done)
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 1, turnEndedAgo: 600), now: now) == .archived)
    }

    @Test func lastActivityCountsWhenTheTurnNeverEnded() {
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 599), now: now) == .done)
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 600), now: now) == .archived)
    }

    @Test func turnEndWinsOverLaterActivity() {
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 30, turnEndedAgo: 900), now: now) == .archived)
    }

    @Test func sessionOlderThanSixHoursArchives() {
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 5, sessionStartedAgo: 21_600), now: now) == .done)
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: 5, sessionStartedAgo: 21_601), now: now) == .archived)
    }

    @Test func agentWithoutDatesIsDone() {
        #expect(HomeSections.kind(of: agent("a", lastActivityAgo: nil), now: now) == .done)
    }

    @Test func showsOnlyClaudeAgents() {
        let sections = HomeSections.make(
            agents: [agent("claude"), agent("codex", kind: "codex"), agent("shell", kind: "")],
            archived: [],
            now: now
        )
        #expect(sections.flatMap(\.cards).map(\.target) == [.agent("claude")])
    }

    @Test func archivedSessionsAlwaysGoToArchived() throws {
        let sections = HomeSections.make(agents: [], archived: [archived("s1", endedAgo: 5)], now: now)
        #expect(kinds(sections) == [.archived])
        let card = try #require(sections.first?.cards.first)
        #expect(card.target == .session("s1"))
        #expect(card.state == .archived)
        #expect(card.title == "Você: revisa o README")
        #expect(card.subtitle == "Sessão encerrada")
        #expect(!card.subtitleIsWarning)
        #expect(!card.canArchive)
    }

    @Test func sectionsFollowTheMockOrderAndSkipEmptyOnes() {
        let sections = HomeSections.make(
            agents: [
                agent("done"),
                agent("old", lastActivityAgo: 3_600),
                agent("work", status: .working),
                agent("block", status: .blocked),
            ],
            archived: [],
            now: now
        )
        #expect(kinds(sections) == [.needsYou, .working, .done, .archived])
        let onlyDone = HomeSections.make(agents: [agent("done")], archived: [], now: now)
        #expect(kinds(onlyDone) == [.done])
        #expect(HomeSections.make(agents: [], archived: [], now: now).isEmpty)
    }

    @Test func cardsAreSortedByMostRecentActivity() {
        let sections = HomeSections.make(
            agents: [
                agent("w-old", status: .working, lastActivityAgo: 300),
                agent("w-nil", status: .working, lastActivityAgo: nil),
                agent("w-new", status: .working, lastActivityAgo: 10),
                agent("a-agent", lastActivityAgo: 7_200),
            ],
            archived: [
                archived("s-ended", endedAgo: 3_000),
                archived("s-active", endedAgo: 100, lastActivityAgo: 90_000),
            ],
            now: now
        )
        #expect(ids(sections, .working) == [.agent("w-new"), .agent("w-old"), .agent("w-nil")])
        #expect(ids(sections, .archived) == [.session("s-ended"), .agent("a-agent"), .session("s-active")])
    }

    @Test func equalDatesKeepTheirOrder() {
        let sections = HomeSections.make(agents: [agent("b"), agent("a"), agent("c")], archived: [], now: now)
        #expect(ids(sections, .done) == [.agent("b"), .agent("a"), .agent("c")])
    }

    @Test func titleUsesThePreviewWithTheUserPrefix() {
        #expect(HomeSections.title(for: MessagePreview(author: .user, text: "roda os testes")) == "Você: roda os testes")
        #expect(HomeSections.title(for: MessagePreview(author: .assistant, text: "Pronto.")) == "Pronto.")
        #expect(HomeSections.title(for: nil) == "Sessão limpa")
    }

    @Test func blockedCardShowsTheToolInAmber() throws {
        let running = ToolActivity(toolName: "Bash", summary: "npm run build", status: .running)
        let sections = HomeSections.make(agents: [agent("a", status: .blocked, activity: running)], archived: [], now: now)
        let card = try #require(sections.first?.cards.first)
        #expect(card.state == .blocked)
        #expect(card.subtitle == "Precisa de você · Shell")
        #expect(card.subtitleIsWarning)
        let withoutTool = HomeSections.card(for: agent("b", status: .blocked), in: .needsYou, now: now)
        #expect(withoutTool.subtitle == "Precisa de você")
    }

    @Test func workingCardShowsTheCurrentTool() {
        let tool = ToolActivity(toolName: "Bash", summary: "swift test --filter AppleSignIn", status: .running)
        let card = HomeSections.card(for: agent("a", status: .working, activity: tool), in: .working, now: now)
        #expect(card.state == .working)
        #expect(card.subtitle == "Shell: swift test --filter AppleSignIn")
        #expect(!card.subtitleIsWarning)
        let read = ToolActivity(toolName: "Read", summary: "Package.swift", status: .succeeded)
        #expect(HomeSections.card(for: agent("b", status: .working, activity: read), in: .working, now: now).subtitle == "Read: Package.swift")
        #expect(HomeSections.card(for: agent("c", status: .working), in: .working, now: now).subtitle == nil)
    }

    @Test func settledCardsHaveNoSecondLine() {
        let tool = ToolActivity(toolName: "Bash", summary: "ls", status: .succeeded)
        #expect(HomeSections.card(for: agent("a", activity: tool), in: .done, now: now).subtitle == nil)
        #expect(HomeSections.card(for: agent("a", activity: tool), in: .archived, now: now).subtitle == nil)
    }

    @Test func cardCarriesMetadata() {
        let card = HomeSections.card(for: agent("w1:p1", lastActivityAgo: 360), in: .done, now: now)
        #expect(card.workspace == "ws-w1:p1")
        #expect(card.contextLeftPercent == 50)
        #expect(card.time == "há 6 min")
        #expect(card.state == .ready)
        #expect(HomeSections.card(for: agent("x", lastActivityAgo: nil), in: .done, now: now).time == "—")
        #expect(HomeSections.card(for: archived("s", endedAgo: 90_000), now: now).time == "ontem")
    }

    @Test func tappingOpensTheChatByAgentOrBySession() {
        let sections = HomeSections.make(agents: [agent("w1:p1")], archived: [archived("4f7c", endedAgo: 30)], now: now)
        #expect(sections.flatMap(\.cards).map(\.target) == [.agent("w1:p1"), .session("4f7c")])
    }

    @Test func onlyDoneCardsCanBeArchived() {
        let sections = HomeSections.make(
            agents: [
                agent("block", status: .blocked),
                agent("work", status: .working),
                agent("done", sessionId: "s-done"),
                agent("old", lastActivityAgo: 3_600),
            ],
            archived: [archived("s1", endedAgo: 30)],
            now: now
        )
        let archivable = sections.flatMap(\.cards).filter(\.canArchive)
        #expect(archivable.map(\.target) == [.agent("done")])
        #expect(archivable.first?.archiveSessionId == "s-done")
        var noSession = agent("fresh")
        noSession.sessionId = nil
        #expect(!HomeSections.card(for: noSession, in: .done, now: now).canArchive)
    }

    @Test func finishingATurnMovesTheCardFromWorkingToDone() {
        var summary = agent("w5:p1", status: .working, lastActivityAgo: 5)
        #expect(ids(HomeSections.make(agents: [summary], archived: [], now: now), .working) == [.agent("w5:p1")])
        summary.status = .idle
        summary.turnEndedAt = now
        let sections = HomeSections.make(agents: [summary], archived: [], now: now)
        #expect(kinds(sections) == [.done])
        #expect(ids(sections, .done) == [.agent("w5:p1")])
    }

    @Test func archivingADoneCardMovesItToArchived() {
        var summary = agent("w1:p1", lastActivityAgo: 30)
        #expect(kinds(HomeSections.make(agents: [summary], archived: [], now: now)) == [.done])
        summary.archivedAt = now
        #expect(kinds(HomeSections.make(agents: [summary], archived: [], now: now)) == [.archived])
    }

    @Test func doneCardArchivesItselfAsTheClockAdvances() {
        let summary = agent("a", lastActivityAgo: 0, turnEndedAgo: 0)
        #expect(HomeSections.kind(of: summary, now: now) == .done)
        #expect(HomeSections.kind(of: summary, now: now.addingTimeInterval(HomeSections.refreshInterval * 20)) == .archived)
    }
}

struct HomeOfflineProblemTests {
    @Test func firstConnectionNeverLooksOffline() {
        var problem: ConnectionProblem?
        for state in [ConnectionState.idle, .connecting, .connected] {
            problem = HomeSections.offlineProblem(for: state, previous: problem)
            #expect(problem == nil)
        }
    }

    @Test func dropShowsTheProblemUntilConnectedAgain() {
        var problem = HomeSections.offlineProblem(for: .waitingToRetry(.unreachable), previous: nil)
        #expect(problem == .unreachable)
        problem = HomeSections.offlineProblem(for: .connecting, previous: problem)
        #expect(problem == .unreachable)
        problem = HomeSections.offlineProblem(for: .failed(.daemonNotRunning), previous: problem)
        #expect(problem == .daemonNotRunning)
        problem = HomeSections.offlineProblem(for: .connected, previous: problem)
        #expect(problem == nil)
    }

    @Test func pairingRequiredClearsTheCapsule() {
        #expect(HomeSections.offlineProblem(for: .pairingRequired(.unauthorized), previous: .unreachable) == nil)
    }
}

struct HomeCardSwipeTests {
    @Test func beginsOnlyForLeftwardHorizontalPans() {
        #expect(HomeCardSwipe.begins(velocityX: -300, velocityY: 40))
        #expect(!HomeCardSwipe.begins(velocityX: 300, velocityY: 40))
        #expect(!HomeCardSwipe.begins(velocityX: -40, velocityY: 300))
        #expect(!HomeCardSwipe.begins(velocityX: 0, velocityY: 0))
    }

    @Test func offsetFollowsTheFingerOnlyToTheLeft() {
        #expect(HomeCardSwipe.offset(forTranslation: -80) == -80)
        #expect(HomeCardSwipe.offset(forTranslation: 30) == 0)
    }

    @Test func archivesPastFortyPercentOfTheWidth() {
        #expect(!HomeCardSwipe.archives(translation: -142, velocity: 0, width: 358))
        #expect(HomeCardSwipe.archives(translation: -144, velocity: 0, width: 358))
    }

    @Test func fastFlickArchivesAndFlickBackCancels() {
        #expect(HomeCardSwipe.archives(translation: -60, velocity: -600, width: 358))
        #expect(!HomeCardSwipe.archives(translation: -200, velocity: 800, width: 358))
        #expect(!HomeCardSwipe.archives(translation: 10, velocity: -2_000, width: 358))
        #expect(!HomeCardSwipe.archives(translation: -300, velocity: 0, width: 0))
    }

    @Test func archiveActionLightsUpAtTheThreshold() {
        #expect(!HomeCardSwipe.revealsArchiveAction(offset: -100, width: 358))
        #expect(HomeCardSwipe.revealsArchiveAction(offset: -150, width: 358))
    }
}

struct SessionIdFormatTests {
    @Test func shortensInTheMiddle() {
        #expect(SessionIdFormat.shortened("b3e8d1f0-2c4a-4b6e-9f1d-7a5c3e2b0d9f") == "b3e8d1f0-2c4a…7a5c3e2b0d9f")
    }

    @Test func keepsShortIds() {
        #expect(SessionIdFormat.shortened("s-login") == "s-login")
        #expect(SessionIdFormat.shortened("abcdefghijklmnopqrstuvwxyz") == "abcdefghijklmnopqrstuvwxyz")
    }
}
