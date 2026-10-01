import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityPresenceTests {
    private let done = AgentActivityAlert(title: "Claude terminou · demo-app", body: "Turno concluído.")
    private let waiting = AgentActivityAlert(title: "Claude precisa de você · demo-app", body: PushAlertText.secondaryBody)

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func agent(_ id: AgentID, _ status: AgentStatus = .working) -> AgentSummary {
        LiveActivitySample.agent(id, status)
    }

    private func card(_ harness: LiveActivityHarness, agents: [AgentSummary]) async throws -> DeviceID {
        let device = try await harness.pair()
        try await harness.registerUpdateToken(for: device)
        try await harness.agents(agents)
        return device
    }

    private func updateAlerts(_ harness: LiveActivityHarness) -> [AgentActivityAlert?] {
        harness.sent.compactMap { sent in
            guard case .update(let alert) = sent.push.event else { return nil }
            return .some(alert)
        }
    }

    @Test func case1AtTheMacTheCardFollowsTheEventsWithoutSound() async throws {
        try await withLiveActivity { harness in
            _ = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            await harness.service.presenceChanged(to: .unlocked)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1")])
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.agentId == "w1:p1")

            let request = LiveActivitySample.permission("req-a", agent: "w2:p1", createdAt: at(12))
            try await harness.advance(2)
            try await harness.agents([agent("w1:p1", .idle), LiveActivitySample.agent("w2:p1", .blocked, pendingCount: 1)], pending: [request])
            #expect(harness.sent.count == 2)
            try await harness.advance(8)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.agentId == "w2:p1")
            #expect(try harness.last().push.contentState.pending?.requestId == "req-a")
            #expect(updateAlerts(harness) == [nil, nil, nil])
        }
    }

    @Test func case2LockingRingsOnceForTheMostUrgentUnseenItem() async throws {
        try await withLiveActivity { harness in
            _ = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1"), agent("w3:p1")])
            await harness.service.presenceChanged(to: .unlocked)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1"), agent("w3:p1")], herdrStatuses: ["w1:p1": .done])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .blocked), agent("w3:p1")], herdrStatuses: ["w1:p1": .done, "w2:p1": .blocked])
            try await harness.advance(10)
            #expect(updateAlerts(harness).allSatisfy { $0 == nil })

            await harness.service.presenceChanged(to: .locked)
            try await harness.settle()
            #expect(try harness.last().push.agentId == "w2:p1")
            #expect(try harness.last().push.event == .update(alert: waiting))
            let count = harness.sent.count

            try await harness.advance(30)
            await harness.service.presenceChanged(to: .unlocked)
            await harness.service.presenceChanged(to: .locked)
            try await harness.advance(30)
            #expect(harness.sent.count == count)
            #expect(updateAlerts(harness).compactMap { $0 } == [waiting])
        }
    }

    @Test func aTurnDoneAlreadySeenOnTheMacDoesNotRingOnLock() async throws {
        try await withLiveActivity { harness in
            _ = try await card(harness, agents: [agent("w1:p1")])
            await harness.service.presenceChanged(to: .unlocked)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)], herdrStatuses: ["w1:p1": .idle])
            try await harness.advance(10)
            await harness.service.presenceChanged(to: .locked)
            try await harness.advance(20)
            #expect(updateAlerts(harness).allSatisfy { $0 == nil })
        }
    }

    @Test func withTheToggleOffAlertsRingAtTheMac() async throws {
        try await withLiveActivity { harness in
            let device = try await card(harness, agents: [agent("w1:p1")])
            let preferences = DevicePreferences(turnDoneAlerts: true, silenceWhileAtMac: false)
            #expect(try await harness.devices.setPreferences(preferences, for: device))
            await harness.service.preferencesChanged(preferences, for: device)
            await harness.service.presenceChanged(to: .unlocked)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)])
            #expect(try harness.last().push.event == .update(alert: done))
        }
    }

    @Test func anUnknownLockRings() async throws {
        try await withLiveActivity { harness in
            _ = try await card(harness, agents: [agent("w1:p1")])
            await harness.service.presenceChanged(to: .unlocked)
            await harness.service.presenceChanged(to: .unknown)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)])
            #expect(try harness.last().push.event == .update(alert: done))
        }
    }

    @Test func aSilencedRequestKeepsTheLimitAndRingsFirstOnLock() async throws {
        try await withLiveActivity { harness in
            _ = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            await harness.service.presenceChanged(to: .unlocked)
            let request = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(5))
            try await harness.advance(5)
            try await harness.agents(
                [LiveActivitySample.agent("w1:p1", .blocked, pendingCount: 1), agent("w2:p1", .idle)],
                pending: [request],
                herdrStatuses: ["w2:p1": .done]
            )
            #expect(harness.sent.count == 1)
            try await harness.advance(5)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.event == .update(alert: nil))

            await harness.service.presenceChanged(to: .locked)
            try await harness.settle()
            #expect(harness.sent.count == 2)
            try await harness.advance(2)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.agentId == "w1:p1")
            #expect(try harness.last().push.timestamp == at(12))
            #expect(try harness.last().push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "rm -rf build")))
        }
    }

    @Test func aSilencedAlertOfACardThatEndedRingsThroughTheNotificationsOnLock() async throws {
        try await withLiveActivity { harness in
            let handoff = FakeAlertHandoff()
            await harness.service.attachAlertHandoff(handoff)
            let device = try await card(harness, agents: [agent("w1:p1")])
            await harness.service.presenceChanged(to: .unlocked)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)], herdrStatuses: ["w1:p1": .done])
            try await harness.advance(10)
            try await harness.service.register(
                LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    env: .sandbox,
                    endedActivityId: LiveActivitySample.activityId
                ),
                from: device
            )
            try await harness.settle()
            #expect(await handoff.handed.isEmpty)

            await harness.service.presenceChanged(to: .locked)
            try await harness.settle()
            #expect(await handoff.handed == [
                FakeAlertHandoff.Handed(
                    alerts: [LiveActivityLostAlert(agentId: "w1:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · demo-app", body: "Turno concluído.")],
                    device: device
                ),
            ])
            #expect(updateAlerts(harness).allSatisfy { $0 == nil })
        }
    }
}
