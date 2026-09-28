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
        #expect(tracker.update([Self.agent("w1:p1", .idle), Self.agent("w2:p1", .working, kind: "shell")], at: Self.start).isEmpty)
        let first = tracker.update([Self.agent("w1:p1", .working), Self.agent("w2:p1", .idle, pendingCount: 1)], at: Self.start)
        #expect(first == ["w1:p1", "w2:p1"])
        #expect(tracker.update([Self.agent("w1:p1", .blocked), Self.agent("w2:p1", .working)], at: Self.start).isEmpty)
        #expect(tracker.update([Self.agent("w1:p1", .idle)], at: Self.start).isEmpty)
        #expect(tracker.update([Self.agent("w1:p1", .working)], at: Self.start) == ["w1:p1"])
    }

    @Test func codexAgentStartsAnActivity() throws {
        var tracker = AgentsActivityTracker()
        let codex = Self.agent("w2:p1", .working, kind: "codex", title: "Codex")
        #expect(tracker.update([codex], at: Self.start) == ["w2:p1"])
        let content = try #require(tracker.content(for: "w2:p1", at: Self.start))
        #expect(content.title == "Codex")
        #expect(content.status == "working")
        #expect(content.provider == .codex)
    }

    @Test func theStartPolicyNeedsTheForegroundNoActivityForTheAgentAndPermission() {
        #expect(AgentsActivityStartPolicy.shouldStart(isForeground: true, hasActivityForAgent: false, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(isForeground: false, hasActivityForAgent: false, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(isForeground: true, hasActivityForAgent: true, activitiesEnabled: true))
        #expect(!AgentsActivityStartPolicy.shouldStart(isForeground: true, hasActivityForAgent: false, activitiesEnabled: false))
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
