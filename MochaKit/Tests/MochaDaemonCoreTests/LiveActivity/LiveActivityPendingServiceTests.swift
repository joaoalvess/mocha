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

    @Test func eachActivityCarriesTheOldestRequestOfItsOwnAgent() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(LiveActivitySample.token(1), activityId: "a1", agent: "w1:p1", for: device)
            try await harness.registerUpdateToken(LiveActivitySample.token(3), activityId: "a3", agent: "w3:p1", for: device)
            let permission = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(10))
            let older = LiveActivitySample.question("req-b", agent: "w3:p1", createdAt: at(5), questions: [question])
            let newer = LiveActivitySample.permission("req-c", agent: "w3:p1", createdAt: at(15))
            let unknown = LiveActivitySample.permission("req-0", agent: "w9:p1", createdAt: at(1))

            try await harness.agents([blocked("w1:p1"), blocked("w3:p1", title: "Escrever testes")], pending: [unknown, newer, permission, older])

            let parser = try #require(harness.sent(to: LiveActivitySample.token(1)).last)
            let tests = try #require(harness.sent(to: LiveActivitySample.token(3)).last)
            #expect(parser.push.contentState.pending == LiveActivityContentState.Pending(
                requestId: "req-a",
                agentId: "w1:p1",
                kind: .permission,
                toolName: "Bash",
                text: "rm -rf build",
                options: []
            ))
            #expect(tests.push.contentState.pending == LiveActivityContentState.Pending(
                requestId: "req-b",
                agentId: "w3:p1",
                kind: .question,
                toolName: nil,
                text: "Qual banco?",
                options: ["Postgres", "SQLite"]
            ))
            #expect(tests.push.contentState.agent.status == "blocked")
            #expect(harness.sent.count == 2)
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

    @Test func requestChangesRespectTheTenSecondLimitWithTheLatestState() async throws {
        try await withLiveActivity { harness in
            let first = LiveActivitySample.permission("req-a", agent: "w1:p1", createdAt: at(3))
            let second = LiveActivitySample.question("req-b", agent: "w1:p1", createdAt: at(6), questions: [question])

            try await appStartedActivity(harness, agents: [blocked("w1:p1", pendingCount: 0)])
            try await harness.advance(3)
            try await harness.agents([blocked("w1:p1")], pending: [first])
            try await harness.advance(3)
            try await harness.agents([blocked("w1:p1")], pending: [second])
            try await harness.advance(3)
            #expect(harness.sent.count == 1)

            try await harness.advance(1)
            #expect(harness.sent.count == 2)
            let update = try harness.last()
            #expect(update.priority == .high)
            #expect(update.push.timestamp == at(10))
            #expect(update.push.contentState.pending?.requestId == "req-b")
            #expect(update.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "Qual banco?")))

            try await harness.agents([blocked("w1:p1")], pending: [first])
            try await harness.agents([blocked("w1:p1")], pending: [second])
            try await harness.advance(10)
            #expect(harness.sent.count == 2)
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

    @Test func aPushToStartCarriesTheCurrentRequestOfItsAgent() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            let request = LiveActivitySample.permission("req-a", agent: "w1:p1")
            try await harness.agents([LiveActivitySample.agent("w2:p1", .working), blocked("w1:p1")], pending: [request])
            let starts = harness.sent.sorted { $0.push.agentId < $1.push.agentId }
            #expect(starts.map(\.push.event.name) == ["start", "start"])
            #expect(starts.map { $0.push.contentState.pending?.requestId } == ["req-a", nil])
        }
    }
}
