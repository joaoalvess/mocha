import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityFocusTests {
    private static let bash = ToolActivity(toolName: "Bash", summary: "npm run build", status: .running)

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func agent(_ id: AgentID, _ status: AgentStatus = .working, preview: String? = nil, title: String = "Refatorar o parser") -> AgentSummary {
        var agent = LiveActivitySample.agent(id, status, title: title)
        agent.preview = preview.map { MessagePreview(author: .assistant, text: $0) }
        return agent
    }

    private func card(_ harness: LiveActivityHarness, agents: [AgentSummary]) async throws -> DeviceID {
        let device = try await harness.pair()
        try await harness.registerUpdateToken(for: device)
        try await harness.agents(agents)
        return device
    }

    @Test func aNewPreviewMovesTheFocusWithPriorityTen() async throws {
        try await withLiveActivity { harness in
            var parser = agent("w1:p1")
            var tests = agent("w2:p1", title: "Escrever testes")
            let device = try await card(harness, agents: [parser, tests])
            #expect(try harness.last().push.agentId == "w1:p1")
            #expect(await harness.service.focus(on: device) == "w1:p1")

            try await harness.advance(10)
            tests.preview = MessagePreview(author: .assistant, text: "Terminei a **primeira** parte.")
            try await harness.agents([parser, tests])
            #expect(harness.sent.count == 2)
            let moved = try harness.last()
            #expect(moved.priority == .high)
            #expect(moved.push.event == .update(alert: nil))
            #expect(moved.push.agentId == "w2:p1")
            #expect(moved.push.contentState.agent.preview == "Terminei a primeira parte.")
            let state = try LiveActivityAppContentState.decoding(moved.push)
            #expect(state.agentId == "w2:p1")
            #expect(state.title == "Escrever testes")
            #expect(await harness.service.focus(on: device) == "w2:p1")

            try await harness.advance(10)
            parser.activity = Self.bash
            parser.contextLeftPercent = 12
            parser.title = "Refatorar o lexer"
            try await harness.agents([parser, tests])
            try await harness.advance(600)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().priority == .low)
            #expect(try harness.last().push.agentId == "w2:p1")
            #expect(await harness.service.focus(on: device) == "w2:p1")

            try await harness.advance(10)
            tests.activity = Self.bash
            try await harness.agents([parser, tests])
            #expect(harness.sent.count == 4)
            let activity = try harness.last()
            #expect(activity.priority == .low)
            #expect(activity.push.agentId == "w2:p1")
            #expect(activity.push.contentState.agent.activity == "Bash: npm run build")
        }
    }

    @Test func aStatusChangeMovesTheFocusAndItsAlertRidesTheUpdate() async throws {
        try await withLiveActivity { harness in
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1"), agent("w2:p1", .idle, preview: "Pronto: rodei os testes.")])
            let done = try harness.last()
            #expect(done.priority == .high)
            #expect(done.push.agentId == "w2:p1")
            #expect(done.push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Pronto: rodei os testes.")))

            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .blocked), agent("w2:p1", .idle, preview: "Pronto: rodei os testes.")])
            let blocked = try harness.last()
            #expect(blocked.priority == .high)
            #expect(blocked.push.agentId == "w1:p1")
            #expect(blocked.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "Esperando uma resposta no terminal.")))
            #expect(harness.sent.count == 3)
            #expect(await harness.service.focus(on: device) == "w1:p1")
        }
    }

    @Test func aTieKeepsTheCurrentFocusAndThenTheLowestAgent() async throws {
        try await withLiveActivity { harness in
            let device = try await card(harness, agents: [agent("w3:p1"), agent("w2:p1")])
            #expect(try harness.last().push.agentId == "w2:p1")

            try await harness.advance(10)
            try await harness.agents([agent("w3:p1", preview: "Um"), agent("w2:p1")])
            #expect(try harness.last().push.agentId == "w3:p1")

            try await harness.advance(10)
            try await harness.agents([agent("w3:p1", preview: "Dois"), agent("w2:p1", preview: "Dois")])
            let tie = try harness.last()
            #expect(tie.push.agentId == "w3:p1")
            #expect(tie.priority == .low)
            #expect(await harness.service.focus(on: device) == "w3:p1")
        }
    }

    @Test func eventsWithinTheTenSecondLimitShowTheLatestOne() async throws {
        try await withLiveActivity { harness in
            _ = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1"), agent("w3:p1")])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1"), agent("w2:p1", preview: "Dois"), agent("w3:p1")])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1"), agent("w2:p1", preview: "Dois"), agent("w3:p1", preview: "Três")])
            try await harness.advance(3)
            #expect(harness.sent.count == 1)

            try await harness.advance(1)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.agentId == "w3:p1")
            #expect(try harness.last().push.timestamp == at(10))
            #expect(try harness.last().priority == .high)
        }
    }

    @Test func onlyClaudeAgentsTakeTheFocus() async throws {
        try await withLiveActivity { harness in
            let codex = LiveActivitySample.agent("w0:p1", .working, kind: "codex")
            let device = try await card(harness, agents: [codex, agent("w1:p1")])
            try await harness.advance(10)
            var busyCodex = codex
            busyCodex.status = .blocked
            try await harness.agents([busyCodex, agent("w1:p1")])
            try await harness.advance(60)
            #expect(harness.sent.map(\.push.agentId) == ["w1:p1"])
            #expect(await harness.service.focus(on: device) == "w1:p1")
        }
    }

    @Test func twoTurnsDoneWithinTenSecondsShowTheLatestAndHandTheOtherToTheNotifications() async throws {
        try await withLiveActivity { harness in
            let fallback = FakeAlertFallback()
            await harness.service.attachAlertFallback(fallback)
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1")])
            try await harness.advance(3)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .idle, preview: "Testes prontos.")])
            try await harness.advance(4)
            #expect(harness.sent.count == 2)
            let update = try harness.last()
            #expect(update.push.agentId == "w2:p1")
            #expect(update.push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Testes prontos.")))
            #expect(Set(await fallback.reports) == [
                .init(kind: .turnDone, agentId: "w2:p1", device: device, wasShown: true),
                .init(kind: .turnDone, agentId: "w1:p1", device: device, wasShown: false),
            ])

            try await harness.advance(60)
            #expect(harness.sent.count == 2)
            #expect(await fallback.reports.count == 2)
        }
    }

    @Test func aTieInTheSameInputShowsOneAlertAndHandsTheOtherToTheNotifications() async throws {
        try await withLiveActivity { harness in
            let fallback = FakeAlertFallback()
            await harness.service.attachAlertFallback(fallback)
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1")])
            try await harness.advance(10)
            try await harness.agents([agent("w1:p1", .idle), agent("w2:p1", .blocked)])
            let update = try harness.last()
            #expect(update.push.agentId == "w1:p1")
            #expect(update.push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Turno concluído.")))
            #expect(Set(await fallback.reports) == [
                .init(kind: .turnDone, agentId: "w1:p1", device: device, wasShown: true),
                .init(kind: .needsInput, agentId: "w2:p1", device: device, wasShown: false),
            ])
        }
    }

    @Test func alertsHeldOutByARequestOrDroppedBeforeTheNextUpdateGoToTheNotifications() async throws {
        try await withLiveActivity { harness in
            let fallback = FakeAlertFallback()
            await harness.service.attachAlertFallback(fallback)
            let device = try await card(harness, agents: [agent("w1:p1"), agent("w2:p1"), agent("w3:p1")])
            let request = LiveActivitySample.permission("req-a", agent: "w1:p1")
            var blocked = LiveActivitySample.agent("w1:p1", .blocked, pendingCount: 1)
            blocked.preview = nil
            try await harness.advance(10)
            try await harness.agents([blocked, agent("w2:p1", .idle), agent("w3:p1")], pending: [request])
            #expect(try harness.last().push.agentId == "w1:p1")
            try await harness.advance(3)
            try await harness.agents([blocked, agent("w2:p1", .idle), agent("w3:p1", .blocked)], pending: [request])
            try await harness.advance(1)
            try await harness.agents([blocked, agent("w2:p1", .idle), agent("w3:p1")], pending: [request])
            #expect(Set(await fallback.reports) == [
                .init(kind: .needsInput, agentId: "w1:p1", device: device, wasShown: true),
                .init(kind: .turnDone, agentId: "w2:p1", device: device, wasShown: false),
                .init(kind: .needsInput, agentId: "w3:p1", device: device, wasShown: false),
            ])
        }
    }
}

actor FakeAlertFallback: LiveActivityAlertFallback {
    struct Report: Hashable {
        let kind: PushAlertKind
        let agentId: AgentID
        let device: DeviceID
        let wasShown: Bool
    }

    private(set) var reports: [Report] = []

    func cardAlert(_ kind: PushAlertKind, of agentId: AgentID, on device: DeviceID, wasShown: Bool) {
        reports.append(Report(kind: kind, agentId: agentId, device: device, wasShown: wasShown))
    }
}
