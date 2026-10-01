import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityPendingServiceTests {
    private let question = LiveActivitySample.singleQuestion("Qual banco?", labels: ["Postgres", "SQLite"])

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func appStartedActivity(_ harness: LiveActivityHarness, agents: [AgentSummary], pending: [PendingRequest] = []) async throws {
        let device = try await harness.pair()
        try await harness.registerUpdateToken(for: device)
        try await harness.agents(agents, pending: pending)
    }

    private func blocked(_ id: AgentID, title: String = "Refatorar o parser", pendingCount: Int = 1) -> AgentSummary {
        LiveActivitySample.agent(id, .blocked, title: title, pendingCount: pendingCount)
    }

    @Test func theOldestRequestHoldsTheCardAndTheNextOneRingsWhenItTakesIt() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            let permission = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(10))
            let older = LiveActivitySample.question("req-b", agent: "w3:p1", createdAt: at(5), questions: [question])
            let newer = LiveActivitySample.permission("req-c", agent: "w3:p1", createdAt: at(15))
            let unknown = LiveActivitySample.permission("req-0", agent: "w9:p1", createdAt: at(1))

            try await harness.agents([blocked("w1:p1"), blocked("w3:p1", title: "Escrever testes")], pending: [unknown, newer, permission, older])
            #expect(harness.sent.count == 1)
            let held = try harness.last()
            #expect(held.push.agentId == "w3:p1")
            #expect(held.push.contentState.pending == LiveActivityContentState.Pending(
                requestId: "req-b",
                agentId: "w3:p1",
                kind: .question,
                toolName: nil,
                text: "Qual banco?",
                options: ["Postgres", "SQLite"]
            ))
            #expect(held.push.contentState.agent.status == "blocked")
            #expect(held.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "Qual banco?")))
            #expect(await harness.service.holder == "w3:p1")

            try await harness.advance(10)
            try await harness.agents([blocked("w1:p1"), LiveActivitySample.agent("w3:p1", .working, title: "Escrever testes")], pending: [unknown, permission])
            #expect(harness.sent.count == 2)
            let next = try harness.last()
            #expect(next.priority == .high)
            #expect(next.push.agentId == "w1:p1")
            #expect(next.push.contentState.pending?.requestId == "req-a")
            #expect(next.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "rm -rf build")))
            #expect(await harness.service.holder == "w1:p1")
            #expect(await harness.service.focus(on: device) == "w1:p1")
        }
    }

    @Test func aRequestHoldsTheCardAgainstEventsOfOtherAgents() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            var parser = LiveActivitySample.agent("w1:p1", .working)
            let request = LiveActivitySample.permission("req-b", agent: "w2:p1", createdAt: at(10))
            try await harness.agents([parser, LiveActivitySample.agent("w2:p1", .working)])
            #expect(try harness.last().push.agentId == "w1:p1")

            try await harness.advance(10)
            try await harness.agents([parser, blocked("w2:p1")], pending: [request])
            let ask = try harness.last()
            #expect(ask.priority == .high)
            #expect(ask.push.agentId == "w2:p1")
            #expect(ask.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "rm -rf build")))
            #expect(await harness.service.holder == "w2:p1")

            try await harness.advance(10)
            parser.preview = MessagePreview(author: .assistant, text: "Terminei.")
            try await harness.agents([parser, blocked("w2:p1")], pending: [request])
            try await harness.advance(10)
            parser.status = .idle
            try await harness.agents([parser, blocked("w2:p1")], pending: [request])
            try await harness.advance(10)
            #expect(harness.sent.count == 2)
            #expect(await harness.service.focus(on: device) == "w2:p1")

            try await harness.agents([parser, LiveActivitySample.agent("w2:p1", .working)])
            #expect(harness.sent.count == 3)
            let queued = try harness.last()
            #expect(queued.push.agentId == "w1:p1")
            #expect(queued.push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Terminei.")))
            #expect(await harness.service.holder == nil)

            try await harness.advance(10)
            #expect(harness.sent.count == 4)
            let resolved = try harness.last()
            #expect(resolved.push.agentId == "w2:p1")
            #expect(resolved.push.contentState.pending == nil)
            #expect(resolved.push.event == .update(alert: nil))

            try await harness.advance(10)
            parser.status = .working
            try await harness.agents([parser, LiveActivitySample.agent("w2:p1", .working)])
            try await harness.advance(10)
            parser.status = .idle
            try await harness.agents([parser, LiveActivitySample.agent("w2:p1", .working)])
            let done = try harness.last()
            #expect(done.push.agentId == "w1:p1")
            #expect(done.push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Terminei.")))
        }
    }

    @Test func whenTheHolderLeavesTheCardGoesBackToTheLatestEvent() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            func agent(_ id: AgentID, preview: String? = nil) -> AgentSummary {
                var agent = LiveActivitySample.agent(id, .working)
                agent.preview = preview.map { MessagePreview(author: .assistant, text: $0) }
                return agent
            }
            let request = LiveActivitySample.permission("req-b", agent: "w2:p1", createdAt: at(0))
            try await harness.agents([agent("w1:p1"), blocked("w2:p1"), agent("w3:p1")], pending: [request])
            #expect(try harness.last().push.agentId == "w2:p1")

            try await harness.advance(5)
            try await harness.agents([agent("w1:p1"), blocked("w2:p1"), agent("w3:p1", preview: "Três")], pending: [request])
            try await harness.advance(5)
            try await harness.agents([agent("w1:p1", preview: "Um"), blocked("w2:p1"), agent("w3:p1", preview: "Três")], pending: [request])
            try await harness.advance(10)
            #expect(harness.sent.count == 1)

            try await harness.agents([agent("w1:p1", preview: "Um"), agent("w3:p1", preview: "Três")])
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.agentId == "w1:p1")
            #expect(try harness.last().push.contentState.agent.preview == "Um")
            #expect(try harness.last().priority == .high)
            #expect(await harness.service.focus(on: device) == "w1:p1")
        }
    }

    @Test func aResolvedRequestLeavesTheNextUpdate() async throws {
        try await withLiveActivity { harness in
            let request = LiveActivitySample.permission("req-a", agent: "w1:p1")
            try await appStartedActivity(harness, agents: [blocked("w1:p1")], pending: [request])
            try await harness.advance(10)
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working)])
            try await harness.advance(10)

            #expect(harness.sent.count == 2)
            let resolved = try harness.last()
            #expect(resolved.priority == .high)
            #expect(resolved.push.contentState.pending == nil)
            #expect(resolved.push.contentState.agent.status == "working")
            let aps = try harness.aps(resolved)
            #expect((aps["content-state"] as? [String: Any])?["pending"] == nil)
        }
    }

    @Test func aRequestThatAppearsChangesOrLeavesIsPriorityTen() async throws {
        try await withLiveActivity { harness in
            let first = LiveActivitySample.permission("req-a", agent: "w1:p1")
            let second = LiveActivitySample.question("req-b", agent: "w1:p1", createdAt: at(15), questions: [question])

            try await appStartedActivity(harness, agents: [blocked("w1:p1", pendingCount: 0)])
            try await harness.advance(10)
            try await harness.agents([blocked("w1:p1")], pending: [first])
            try await harness.advance(10)
            try await harness.agents([blocked("w1:p1")], pending: [second])
            try await harness.advance(10)
            try await harness.agents([blocked("w1:p1", title: "Refatorar o lexer")], pending: [second])
            try await harness.advance(10)
            try await harness.agents([blocked("w1:p1", title: "Refatorar o lexer", pendingCount: 0)])
            try await harness.advance(10)

            #expect(harness.sent.map { $0.push.contentState.pending?.requestId } == [nil, "req-a", "req-b", "req-b", nil])
            #expect(harness.sent.map(\.priority) == [.high, .high, .high, .low, .high])
            #expect(harness.sent.map { $0.push.event == .update(alert: nil) } == [true, false, false, true, true])
            #expect(harness.sent.map(\.push.timestamp) == [at(0), at(10), at(20), at(30), at(40)])
        }
    }

    @Test func requestAlertsSkipTheTenSecondLimitButStayTwoSecondsApart() async throws {
        try await withLiveActivity { harness in
            let first = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(3))
            let second = LiveActivitySample.question("req-b", agent: "w1:p1", createdAt: at(4), questions: [question])

            try await appStartedActivity(harness, agents: [blocked("w1:p1", pendingCount: 0)])
            try await harness.advance(3)
            try await harness.agents([blocked("w1:p1")], pending: [first])
            #expect(harness.sent.count == 2)
            let ask = try harness.last()
            #expect(ask.priority == .high)
            #expect(ask.push.timestamp == at(3))
            #expect(ask.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "rm -rf build")))

            try await harness.advance(1)
            try await harness.agents([blocked("w1:p1")], pending: [second])
            #expect(harness.sent.count == 2)

            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            let update = try harness.last()
            #expect(update.priority == .high)
            #expect(update.push.timestamp == at(5))
            #expect(update.push.contentState.pending?.requestId == "req-b")
            #expect(update.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "Qual banco?")))

            try await harness.agents([blocked("w1:p1", title: "Refatorar o lexer")], pending: [second])
            try await harness.advance(9)
            #expect(harness.sent.count == 3)
            try await harness.advance(1)
            #expect(harness.sent.count == 4)
            #expect(try harness.last().push.event == .update(alert: nil))
            #expect(try harness.last().push.timestamp == at(15))
        }
    }

    @Test func aRequestAloneMakesItsAgentWaiting() async throws {
        try await withLiveActivity { harness in
            let request = LiveActivitySample.permission("req-a", agent: "w1:p1")
            try await appStartedActivity(harness, agents: [LiveActivitySample.agent("w1:p1", .working)], pending: [request])
            let update = try harness.last()
            #expect(update.push.contentState.agent.status == "blocked")
            #expect(update.push.contentState.pending?.requestId == "req-a")
            #expect(update.push.relevanceScore == 100)
        }
    }

    @Test func aPushToStartCarriesTheRequestThatHoldsTheCard() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            let request = LiveActivitySample.permission("req-a", agent: "w2:p1")
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working), blocked("w2:p1")], pending: [request])
            #expect(harness.sent.map(\.push.event.name) == ["start"])
            #expect(try harness.last().push.agentId == "w2:p1")
            #expect(try harness.last().push.contentState.pending?.requestId == "req-a")
        }
    }
}
