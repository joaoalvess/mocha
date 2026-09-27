import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct AgentsActivityTrackerTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 780_000_000)

    private static func agent(
        _ id: String,
        _ status: AgentStatus,
        kind: String = "claude",
        title: String = "Agente",
        pendingCount: Int = 0,
        turnStartedAt: Date? = nil
    ) -> AgentSummary {
        AgentSummary(id: id, kind: kind, status: status, title: title, workspaceLabel: "ws-\(id)", pendingCount: pendingCount, turnStartedAt: turnStartedAt)
    }

    private static func shouldStart(_ becameWorking: Bool, isForeground: Bool = true, hasOngoingActivity: Bool = false, activitiesEnabled: Bool = true) -> Bool {
        AgentsActivityStartPolicy.shouldStart(
            agentBecameWorking: becameWorking,
            isForeground: isForeground,
            hasOngoingActivity: hasOngoingActivity,
            activitiesEnabled: activitiesEnabled
        )
    }

    @Test func anAgentStartingToWorkStartsTheActivityInTheForeground() {
        var tracker = AgentsActivityTracker()
        let idle = tracker.update([Self.agent("w1:p1", .idle)], at: Self.start)
        #expect(!idle)
        let becameWorking = tracker.update([Self.agent("w1:p1", .working)], at: Self.start.addingTimeInterval(5))
        #expect(becameWorking)
        #expect(Self.shouldStart(becameWorking))
    }

    @Test func noStartInBackgroundWithAnActivityOrWithActivitiesDisabled() {
        #expect(!Self.shouldStart(true, isForeground: false))
        #expect(!Self.shouldStart(true, hasOngoingActivity: true))
        #expect(!Self.shouldStart(true, activitiesEnabled: false))
        #expect(!Self.shouldStart(false))
    }

    @Test func aWorkingAgentOnlyCountsOnceUntilItLeavesWorking() {
        var tracker = AgentsActivityTracker()
        let statuses: [AgentStatus] = [.working, .working, .blocked, .working, .done, .working]
        var becameWorking: [Bool] = []
        for (offset, status) in statuses.enumerated() {
            becameWorking.append(tracker.update([Self.agent("w1:p1", status)], at: Self.start.addingTimeInterval(Double(offset))))
        }
        #expect(becameWorking == [true, false, false, true, false, true])
    }

    @Test func otherAgentKindsAreIgnored() {
        var tracker = AgentsActivityTracker()
        let becameWorking = tracker.update([Self.agent("w1:p1", .working, kind: "codex")], at: Self.start)
        #expect(!becameWorking)
        #expect(tracker.content(at: Self.start) == AgentsActivityContent(working: 0, waiting: 0, highlight: nil, updatedAt: Self.start))
    }

    @Test func contentCountsAndHighlightsTheOldestWaitingAgent() {
        var tracker = AgentsActivityTracker()
        tracker.update([Self.agent("w1:p1", .working, title: "Primeiro")], at: Self.start)
        tracker.update([
            Self.agent("w1:p1", .working, title: "Primeiro"),
            Self.agent("w2:p1", .idle, title: "Com pedido", pendingCount: 1),
            Self.agent("w3:p1", .blocked, title: "Bloqueado"),
        ], at: Self.start.addingTimeInterval(10))
        let now = Self.start.addingTimeInterval(20)
        let content = tracker.content(at: now)
        #expect(content.working == 1)
        #expect(content.waiting == 2)
        #expect(content.pending == nil)
        #expect(content.updatedAt == now)
        #expect(content.highlight == AgentsActivityContent.Highlight(
            agentId: "w2:p1",
            title: "Com pedido",
            workspaceLabel: "ws-w2:p1",
            status: "blocked",
            since: Self.start.addingTimeInterval(10)
        ))
    }

    @Test func withoutWaitingTheOldestWorkingAgentIsHighlightedWithItsTurnStart() {
        var tracker = AgentsActivityTracker()
        let turnStart = Self.start.addingTimeInterval(-90)
        tracker.update([
            Self.agent("w2:p1", .working, title: "Novo"),
            Self.agent("w1:p1", .working, title: String(repeating: "x", count: 80), turnStartedAt: turnStart),
        ], at: Self.start)
        let content = tracker.content(at: Self.start)
        #expect(content.working == 2)
        #expect(content.highlight?.agentId == "w1:p1")
        #expect(content.highlight?.since == turnStart)
        #expect(content.highlight?.status == "working")
        #expect(content.highlight?.title.count == AgentsActivityTracker.titleLimit)
    }

    @Test func sinceIsKeptWhileTheStatusStaysTheSame() {
        var tracker = AgentsActivityTracker()
        tracker.update([Self.agent("w1:p1", .blocked)], at: Self.start)
        tracker.update([Self.agent("w1:p1", .blocked)], at: Self.start.addingTimeInterval(30))
        #expect(tracker.content(at: Self.start.addingTimeInterval(30)).highlight?.since == Self.start)
        tracker.update([Self.agent("w1:p1", .working, turnStartedAt: Self.start.addingTimeInterval(3600))], at: Self.start.addingTimeInterval(40))
        #expect(tracker.content(at: Self.start.addingTimeInterval(40)).highlight?.since == Self.start.addingTimeInterval(40))
    }
}
