import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityAlertTimelineTests {
    private let done = AgentActivityAlert(title: "Claude terminou · demo-app", body: "Turno concluído.")
    private let waiting = AgentActivityAlert(title: "Claude precisa de você · demo-app", body: PushAlertText.secondaryBody)

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func agent(_ id: AgentID, _ status: AgentStatus = .working, preview: String? = nil) -> AgentSummary {
        var agent = LiveActivitySample.agent(id, status)
        agent.preview = preview.map { MessagePreview(author: .assistant, text: $0) }
        return agent
    }

    private func blocked(_ id: AgentID, title: String = "Refatorar o parser") -> AgentSummary {
        LiveActivitySample.agent(id, .blocked, title: title, pendingCount: 1)
    }

    private func asking(_ body: String) -> AgentActivityAlert {
        AgentActivityAlert(title: "Claude precisa de você · demo-app", body: body)
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

    @Test func case3TwoTurnsDoneThreeSecondsApartRingOneCycleApartAfterTheCooldown() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let handoff = FakeAlertHandoff()
            await harness.service.attachAlertHandoff(handoff)
            _ = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1"), agent("w3:p1"), agent("w4:p1")])
            #expect(harness.sent.count == 1)

            try await harness.advance(12)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1"), agent("w3:p1"), agent("w4:p1")])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .idle), agent("w3:p1"), agent("w4:p1")])
            #expect(harness.sent.count == 1)

            try await harness.advance(2)
            #expect(harness.sent.count == 2)
            let first = try harness.last()
            #expect(first.push.agentId == "w1:p1")
            #expect(first.push.timestamp == at(17))
            #expect(first.priority == .high)
            #expect(first.push.event == .update(alert: done))

            try await harness.advance(3)
            try await harness.advance(2)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .idle), agent("w3:p1", preview: "Três"), agent("w4:p1")])
            try await harness.advance(5)
            #expect(harness.sent.count == 3)
            let second = try harness.last()
            #expect(second.push.agentId == "w2:p1")
            #expect(second.push.timestamp == at(27))
            #expect(second.push.event == .update(alert: done))

            try await harness.advance(10)
            #expect(harness.sent.count == 4)
            let back = try harness.last()
            #expect(back.push.agentId == "w3:p1")
            #expect(back.push.event == .update(alert: nil))
            #expect(await handoff.handed.isEmpty)
        }
    }

    @Test func case4TheSecondRequestWaitsWithoutSoundAndRingsWhenItTakesTheCard() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let handoff = FakeAlertHandoff()
            await harness.service.attachAlertHandoff(handoff)
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            let first = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(5))
            let second = LiveActivitySample.permission("req-b", agent: "w2:p1", createdAt: at(7), summary: "git push")

            try await harness.advance(5)
            try await harness.agents([blocked("w1:p1"), agent("w2:p1")], pending: [first])
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.timestamp == at(5))
            #expect(try harness.last().push.event == .update(alert: asking("rm -rf build")))

            try await harness.advance(2)
            try await harness.agents([blocked("w1:p1"), blocked("w2:p1")], pending: [first, second])
            try await harness.advance(20)
            #expect(harness.sent.count == 2)
            #expect(await harness.service.focus(on: device) == "w1:p1")

            try await harness.agents([agent("w1:p1"), blocked("w2:p1")], pending: [second])
            #expect(harness.sent.count == 3)
            let next = try harness.last()
            #expect(next.push.agentId == "w2:p1")
            #expect(next.push.timestamp == at(27))
            #expect(next.push.event == .update(alert: asking("git push")))
            #expect(await handoff.handed.isEmpty)
        }
    }

    @Test func case9ATurnThatRestartsWithinFiveSecondsNeverRings() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            _ = try await card(harness, agents: [agent("w1:p1")])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1")])
            try await harness.advance(20)

            #expect(harness.sent.count == 1)
            #expect(updateAlerts(harness) == [nil])
        }
    }

    @Test func aBlockedWithoutARequestWaitsOneSecondAndRingsOnceInTenSeconds() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            _ = try await card(harness, agents: [agent("w1:p1")])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .blocked)])
            try await harness.advance(0.5)
            try await harness.agents([agent("w1:p1")])
            try await harness.advance(10)
            #expect(harness.sent.count == 1)

            try await harness.agents([agent("w1:p1", .blocked)])
            try await harness.advance(1)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.timestamp == at(21.5))
            #expect(try harness.last().push.event == .update(alert: waiting))

            try await harness.advance(1)
            try await harness.agents([agent("w1:p1")])
            try await harness.advance(2)
            try await harness.agents([agent("w1:p1", .blocked)])
            try await harness.advance(1)
            try await harness.advance(6)
            #expect(harness.sent.count == 3)
            let repeated = try harness.last()
            #expect(repeated.push.timestamp == at(31.5))
            #expect(repeated.push.contentState.agent.status == "blocked")
            #expect(repeated.push.event == .update(alert: nil))
        }
    }

    @Test func theAppOpenOnAnotherAgentStillRingsButTheAgentOnScreenDoesNot() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1")], foregroundAgents: [device: "w2:p1"])
            try await harness.advance(5)
            #expect(try harness.last().push.agentId == "w1:p1")
            #expect(try harness.last().push.event == .update(alert: done))

            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .idle)], foregroundAgents: [device: "w2:p1"])
            try await harness.advance(5)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.agentId == "w2:p1")
            #expect(try harness.last().push.event == .update(alert: nil))

            try await harness.advance(30)
            #expect(harness.sent.count == 3)
        }
    }

    @Test func turnDoneAlertsOffSendTheContentWithoutAnAlertAndNoExtraUpdate() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let device = try await card(harness, agents: [agent("w1:p1")])
            #expect(try await harness.devices.setPreferences(DevicePreferences(turnDoneAlerts: false), for: device))
            await harness.service.preferencesChanged(DevicePreferences(turnDoneAlerts: false), for: device)

            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)])
            try await harness.advance(5)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.event == .update(alert: nil))
            #expect(try harness.last().push.contentState.agent.status == "idle")

            try await harness.advance(30)
            #expect(harness.sent.count == 2)

            let request = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(45))
            try await harness.agents([blocked("w1:p1")], pending: [request])
            #expect(try harness.last().push.event == .update(alert: asking("rm -rf build")))
        }
    }

    @Test func aFailedAlertUpdateRingsOnTheRetry() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            _ = try await card(harness, agents: [agent("w1:p1")])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle)])
            harness.sender.respond(with: .failed(retryable: true))
            try await harness.advance(5)
            #expect(harness.sent.count == 2)

            try await harness.advance(10)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.timestamp == at(25))
            #expect(try harness.last().push.event == .update(alert: done))

            try await harness.advance(30)
            #expect(harness.sent.count == 3)
        }
    }

    @Test func alertsBeforeTheCardHasAnUpdateTokenAreLeftToThePushService() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents([agent("w1:p1"), agent("w2:p1")])
            #expect(harness.sent.count == 1)
            #expect(await harness.service.cardDevices().isEmpty)

            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1")])
            try await harness.advance(5)
            try await harness.registerUpdateToken(for: device)
            #expect(await harness.service.cardDevices() == [device])

            try await harness.advance(10)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.agentId == "w1:p1")
            #expect(updateAlerts(harness) == [nil])
        }
    }

    @Test func aCardRefusedByAPNsHandsEveryPendingAlertToTheNotifications() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let handoff = FakeAlertHandoff()
            await harness.service.attachAlertHandoff(handoff)
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1"), agent("w3:p1")])
            let first = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(5))
            let second = LiveActivitySample.permission("req-b", agent: "w2:p1", createdAt: at(6), summary: "git push")

            try await harness.advance(5)
            try await harness.agents([blocked("w1:p1"), agent("w2:p1"), agent("w3:p1")], pending: [first])
            try await harness.advance(1)
            try await harness.agents([blocked("w1:p1"), blocked("w2:p1"), agent("w3:p1")], pending: [first, second])
            try await harness.advance(1)
            try await harness.agents([blocked("w1:p1"), blocked("w2:p1"), agent("w3:p1", .idle)], pending: [first, second])
            try await harness.advance(5)
            try await harness.advance(2)
            try await harness.agents([blocked("w1:p1", title: "Refatorar o lexer"), blocked("w2:p1"), agent("w3:p1", .idle)], pending: [first, second])
            #expect(harness.sent.count == 2)

            harness.sender.respond(with: .invalidToken)
            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            #expect(await handoff.handed == [
                FakeAlertHandoff.Handed(
                    alerts: [
                        LiveActivityLostAlert(agentId: "w2:p1", kind: .needsInput, requestId: "req-b", title: "Claude precisa de você · demo-app", body: "git push"),
                        LiveActivityLostAlert(agentId: "w3:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · demo-app", body: "Turno concluído."),
                    ],
                    device: device
                ),
            ])
            #expect(await harness.service.cardDevices().isEmpty)
            #expect(try await harness.storedCard(device) == nil)

            try await harness.advance(30)
            #expect(harness.sent.count == 3)
        }
    }

    @Test func anActivityEndedOnTheIPhoneHandsItsPendingAlertToTheNotifications() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration()) { harness in
            let handoff = FakeAlertHandoff()
            await harness.service.attachAlertHandoff(handoff)
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1")])
            try await harness.advance(5)
            #expect(harness.sent.count == 1)

            try await harness.service.register(
                LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    env: .sandbox,
                    endedActivityId: LiveActivitySample.activityId
                ),
                from: device
            )
            try await harness.settle()
            #expect(await handoff.handed == [
                FakeAlertHandoff.Handed(
                    alerts: [LiveActivityLostAlert(agentId: "w1:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · demo-app", body: "Turno concluído.")],
                    device: device
                ),
            ])
            #expect(await harness.service.cardDevices().isEmpty)
            #expect(try await harness.storedCard(device) == nil)

            try await harness.registerUpdateToken(for: device)
            #expect(await harness.service.cardDevices().isEmpty)
            try await harness.advance(30)
            #expect(harness.sent.count == 1)
        }
    }

    @Test func aRenewalSendsThePendingAlertBeforeEndingTheCard() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration(renewalAge: 60)) { harness in
            _ = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1"), agent("w3:p1")])
            try await harness.advance(50)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1"), agent("w3:p1")])
            try await harness.advance(5)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.event == .update(alert: done))

            try await harness.advance(1)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .idle), agent("w3:p1")])
            try await harness.advance(5)
            try await harness.advance(4)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.agentId == "w2:p1")
            #expect(try harness.last().push.timestamp == at(65))
            #expect(try harness.last().push.event == .update(alert: done))

            try await harness.advance(10)
            let end = try #require(harness.sent.dropFirst(3).first)
            guard case .end = end.push.event else {
                Issue.record("expected the end of the card, got \(end.push.event)")
                return
            }
            #expect(end.token == LiveActivitySample.updateToken)
            #expect(harness.sent.last?.token == LiveActivitySample.pushToStartToken)
        }
    }

    @Test func aRequestWaitingItsTurnRingsOnTheRenewedCard() async throws {
        try await withLiveActivity(configuration: LiveActivityConfiguration(renewalAge: 60)) { harness in
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            let first = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(5))
            let second = LiveActivitySample.permission("req-b", agent: "w2:p1", createdAt: at(7), summary: "git push")
            try await harness.advance(5)
            try await harness.agents([blocked("w1:p1"), agent("w2:p1")], pending: [first])
            try await harness.advance(2)
            try await harness.agents([blocked("w1:p1"), blocked("w2:p1")], pending: [first, second])
            try await harness.advance(53)
            #expect(harness.sent.count == 4)
            #expect(harness.sent.last?.token == LiveActivitySample.pushToStartToken)

            try await harness.registerUpdateToken(LiveActivitySample.otherUpdateToken, activityId: "renewed", for: device)
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1"), blocked("w2:p1")], pending: [second])
            let next = try harness.last()
            #expect(next.token == LiveActivitySample.otherUpdateToken)
            #expect(next.push.agentId == "w2:p1")
            #expect(next.push.event == .update(alert: asking("git push")))
        }
    }
}
