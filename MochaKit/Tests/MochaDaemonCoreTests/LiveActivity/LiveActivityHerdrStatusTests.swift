import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityHerdrStatusTests {
    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func agent(_ id: AgentID, _ status: AgentStatus, kind: String = "claude") -> AgentSummary {
        LiveActivitySample.agent(id, status, kind: kind)
    }

    @Test func aDoneThatTurnsIdleIsNotAnEvent() {
        var tracker = AgentActivityTracker()
        _ = tracker.snapshots(of: LiveActivityInput(agents: [agent("w1:p1", .working), agent("w2:p1", .working)]), at: at(0), titleLimit: 60)
        _ = tracker.snapshots(
            of: LiveActivityInput(agents: [agent("w1:p1", .done), agent("w2:p1", .working)], herdrStatuses: ["w1:p1": .done, "w2:p1": .working]),
            at: at(5),
            titleLimit: 60
        )
        #expect(tracker.herdrStatuses["w1:p1"] == .done)
        #expect(tracker.alerts["w1:p1"]?.kind == .turnDone)
        #expect(tracker.alerts["w1:p1"]?.at == at(5))
        #expect(tracker.eventDates["w1:p1"] == at(5))
        let generation = tracker.eventGenerations["w1:p1"]

        let snapshots = tracker.snapshots(
            of: LiveActivityInput(agents: [agent("w1:p1", .idle), agent("w2:p1", .working)], herdrStatuses: ["w1:p1": .idle, "w2:p1": .working]),
            at: at(9),
            titleLimit: 60
        )
        #expect(tracker.herdrStatuses["w1:p1"] == .idle)
        #expect(tracker.eventGenerations["w1:p1"] == generation)
        #expect(tracker.eventDates["w1:p1"] == at(5))
        #expect(tracker.focus(among: snapshots, current: "w2:p1") == "w1:p1")
    }

    @Test func theRawStatusComesFromHerdrEvenWhenCodexReplacesIt() {
        var tracker = AgentActivityTracker()
        _ = tracker.snapshots(
            of: LiveActivityInput(agents: [agent("w1:p1", .idle, kind: "codex"), agent("w2:p1", .done)], herdrStatuses: ["w1:p1": .done]),
            at: at(0),
            titleLimit: 60
        )
        #expect(tracker.herdrStatuses["w1:p1"] == .done)
        #expect(tracker.herdrStatuses["w2:p1"] == .done)
    }

    @Test func theRawStatusesFollowTheTree() {
        var tracker = AgentActivityTracker()
        _ = tracker.snapshots(of: LiveActivityInput(agents: [agent("w1:p1", .done), agent("w2:p1", .idle)]), at: at(0), titleLimit: 60)
        _ = tracker.snapshots(of: LiveActivityInput(agents: [agent("w2:p1", .idle)]), at: at(1), titleLimit: 60)
        #expect(tracker.herdrStatuses == ["w2:p1": .idle])
    }
}
