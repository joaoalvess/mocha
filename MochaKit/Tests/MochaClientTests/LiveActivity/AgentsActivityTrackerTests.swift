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

    @Test func eachAgentThatBecomesBusyIsReportedOnce() {
        var tracker = AgentsActivityTracker()
        #expect(tracker.update([Self.agent("w1:p1", .idle), Self.agent("w2:p1", .working, kind: "codex")], at: Self.start).isEmpty)
        let first = tracker.update([Self.agent("w1:p1", .working), Self.agent("w2:p1", .idle, pendingCount: 1)], at: Self.start)
        #expect(first == ["w1:p1", "w2:p1"])
        #expect(tracker.update([Self.agent("w1:p1", .blocked), Self.agent("w2:p1", .working)], at: Self.start).isEmpty)
        #expect(tracker.update([Self.agent("w1:p1", .idle)], at: Self.start).isEmpty)
        #expect(tracker.update([Self.agent("w1:p1", .working)], at: Self.start) == ["w1:p1"])
    }

    @Test func theStartPolicyNeedsANewlyBusyAgentTheForegroundNoCardAndPermission() {
        #expect(AgentsActivityStartPolicy.shouldStart(becameBusy: true, isForeground: true, hasActivity: false, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(becameBusy: false, isForeground: true, hasActivity: false, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(becameBusy: true, isForeground: false, hasActivity: false, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(becameBusy: true, isForeground: true, hasActivity: true, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(becameBusy: true, isForeground: true, hasActivity: false, activitiesEnabled: false))
    }

    @Test func theFocusIsTheAgentThatChangedLastWithTheSmallestIdOnATie() {
        var tracker = AgentsActivityTracker()
        #expect(tracker.focus == nil)
        tracker.update([Self.agent("w2:p1", .working), Self.agent("w1:p1", .working)], at: Self.start)
        #expect(tracker.focus == "w1:p1")
        tracker.update([Self.agent("w2:p1", .working), Self.agent("w1:p1", .working), Self.agent("w3:p1", .working)], at: Self.start.addingTimeInterval(5))
        #expect(tracker.focus == "w3:p1")
        tracker.update([Self.agent("w2:p1", .blocked), Self.agent("w1:p1", .working), Self.agent("w3:p1", .working)], at: Self.start.addingTimeInterval(10))
        #expect(tracker.focus == "w2:p1")
        tracker.update([Self.agent("w1:p1", .working), Self.agent("w3:p1", .working)], at: Self.start.addingTimeInterval(15))
        #expect(tracker.focus == "w3:p1")
    }

    @Test func thePendingRequestSeenFirstHoldsTheFocus() {
        var tracker = AgentsActivityTracker()
        tracker.update([Self.agent("w2:p1", .blocked, pendingCount: 1), Self.agent("w1:p1", .working)], at: Self.start)
        #expect(tracker.focus == "w2:p1")
        tracker.update([
            Self.agent("w2:p1", .blocked, pendingCount: 1),
            Self.agent("w1:p1", .blocked, pendingCount: 1),
            Self.agent("w3:p1", .working),
        ], at: Self.start.addingTimeInterval(5))
        #expect(tracker.focus == "w2:p1")
        tracker.update([Self.agent("w2:p1", .working), Self.agent("w1:p1", .blocked, pendingCount: 1)], at: Self.start.addingTimeInterval(10))
        #expect(tracker.focus == "w1:p1")
        tracker.update([Self.agent("w2:p1", .working), Self.agent("w1:p1", .working)], at: Self.start.addingTimeInterval(15))
        #expect(tracker.focus == "w1:p1")
    }

    @Test func theContentOfAnAgentUsesItsTurnStartAndTruncatesTheTitle() throws {
        var tracker = AgentsActivityTracker()
        let turn = Self.start.addingTimeInterval(-90)
        var working = Self.agent("w1:p1", .working, title: String(repeating: "Título longo ", count: 8), turnStartedAt: turn)
        working.model = "claude-opus-5-5"
        working.contextLeftPercent = 42
        tracker.update([working], at: Self.start)
        let content = try #require(tracker.content(for: "w1:p1", at: Self.start.addingTimeInterval(5)))
        #expect(content == AgentsActivityContent(
            agentId: "w1:p1",
            status: "working",
            title: String(working.title.prefix(60)),
            workspaceLabel: "ws-w1:p1",
            since: turn,
            model: "claude-opus-5-5",
            contextLeftPercent: 42,
            updatedAt: Self.start.addingTimeInterval(5)
        ))
        #expect(tracker.content(for: "w9:p9", at: Self.start) == nil)
    }

    @Test func aStatusChangeRestartsTheClockAndAPendingCountMeansBlocked() throws {
        var tracker = AgentsActivityTracker()
        tracker.update([Self.agent("w1:p1", .working)], at: Self.start)
        tracker.update([Self.agent("w1:p1", .working)], at: Self.start.addingTimeInterval(10))
        #expect(try #require(tracker.content(for: "w1:p1", at: Self.start)).since == Self.start)
        tracker.update([Self.agent("w1:p1", .idle, pendingCount: 1)], at: Self.start.addingTimeInterval(20))
        let blocked = try #require(tracker.content(for: "w1:p1", at: Self.start.addingTimeInterval(20)))
        #expect(blocked.status == "blocked")
        #expect(blocked.since == Self.start.addingTimeInterval(20))
    }
}
