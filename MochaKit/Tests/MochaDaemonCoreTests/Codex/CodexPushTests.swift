import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexPushTests {
    private static func codexAgent(status: AgentStatus = .working, pendingCount: Int = 0) -> AgentSummary {
        var agent = Sample.agent(CodexSample.pane, status: status, kind: "codex", title: "codex")
        agent.pendingCount = pendingCount
        return agent
    }

    private static func question(_ text: String, id: String = "banco") -> PendingQuestion {
        PendingQuestion(header: "Banco", question: text, options: [PendingOption(label: "SQLite")], multiSelect: false, id: id)
    }

    private static func request(_ kind: PendingKind) -> PendingRequest {
        PendingRequest(id: "codex:\(CodexSample.threadId):item", agentId: CodexSample.pane, createdAt: Sample.start, kind: kind)
    }

    private static func alerts(_ harness: PushHarness) throws -> [(aps: [String: Any], payload: [String: Any])] {
        try harness.payloads().map { (try #require($0["aps"] as? [String: Any]), $0) }
    }

    @Test func aSingleCodexQuestionIsAnsweredFromTheNotification() async throws {
        try await withPush(audience: FakePushAudience(agents: [Self.codexAgent()])) { harness in
            try await harness.device()
            let request = Self.request(.question(questions: [Self.question("Qual banco de dados usar?")]))

            await harness.service.handle(.needsInput(request))
            await harness.service.waitForDeliveries()

            let sent = try #require(try Self.alerts(harness).first)
            #expect(sent.aps["category"] as? String == "QUESTION")
            #expect((sent.aps["alert"] as? [String: Any])?["body"] as? String == "Qual banco de dados usar?")
            #expect((sent.aps["alert"] as? [String: Any])?["title"] as? String == "Codex precisa de você · Core")
            #expect(sent.payload["requestId"] as? String == request.id)
        }
    }

    @Test func severalCodexQuestionsOpenTheApp() async throws {
        try await withPush(audience: FakePushAudience(agents: [Self.codexAgent()])) { harness in
            try await harness.device()
            let request = Self.request(.question(questions: [Self.question("Primeira?", id: "a"), Self.question("Segunda?", id: "b")]))

            await harness.service.handle(.needsInput(request))
            await harness.service.waitForDeliveries()

            let sent = try #require(try Self.alerts(harness).first)
            #expect(sent.aps["category"] as? String == "NEEDS_INPUT")
            #expect((sent.aps["alert"] as? [String: Any])?["body"] as? String == "Primeira?")
        }
    }

    @Test func aCodexPermissionUsesThePermissionCategory() async throws {
        try await withPush(audience: FakePushAudience(agents: [Self.codexAgent()])) { harness in
            try await harness.device()
            await harness.service.handle(.needsInput(Self.request(.permission(toolName: "Bash", summary: "npm test", inputJSON: "{}"))))
            await harness.service.waitForDeliveries()

            let sent = try #require(try Self.alerts(harness).first)
            #expect(sent.aps["category"] as? String == "PERMISSION")
            #expect((sent.aps["alert"] as? [String: Any])?["body"] as? String == "npm test")
        }
    }

    @Test func requestsTheAppCannotAnswerAlertWithoutActions() async throws {
        try await withPush(audience: FakePushAudience(agents: [Self.codexAgent(status: .blocked)])) { harness in
            try await harness.device()

            await harness.service.handle(.blocked(CodexSample.pane))
            await harness.service.handle(.needsInputWithoutActions(CodexSample.pane, body: "github: Qual repositório abrir?"))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()

            let sent = try Self.alerts(harness)
            #expect(sent.count == 1)
            #expect(sent.first?.aps["category"] as? String == "NEEDS_INPUT")
            #expect(sent.first?.payload["requestId"] == nil)
            #expect((sent.first?.aps["alert"] as? [String: Any])?["body"] as? String == "github: Qual repositório abrir?")
        }
    }

    @Test func aBlockedCodexAgentWithoutARequestAlertsAfterTheGrace() async throws {
        let audience = FakePushAudience(agents: [Self.codexAgent(status: .blocked)])
        try await withPush(audience: audience) { harness in
            try await harness.device()

            await harness.service.handle(.blocked(CodexSample.pane))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()

            let sent = try Self.alerts(harness)
            #expect(sent.count == 1)
            #expect(sent.first?.payload["requestId"] == nil)
            #expect((sent.first?.aps["alert"] as? [String: Any])?["body"] as? String == "Esperando uma resposta no terminal.")
        }
    }

    @Test(arguments: [(AgentStatus.working, 0), (.blocked, 1)])
    func aBlockedAlertIsDroppedWhenTheAgentMovedOnOrHasARequest(status: AgentStatus, pendingCount: Int) async throws {
        try await withPush(audience: FakePushAudience(agents: [Self.codexAgent(status: status, pendingCount: pendingCount)])) { harness in
            try await harness.device()

            await harness.service.handle(.blocked(CodexSample.pane))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()

            #expect(harness.transport.requests.isEmpty)
        }
    }
}
