import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

enum PendingFixtures {
    static let start = Date(timeIntervalSince1970: 1_790_381_000)

    static func permission(_ id: RequestID, agent: AgentID = "w1:p1", secondsAfterStart: TimeInterval = 0) -> PendingRequest {
        PendingRequest(
            id: id,
            agentId: agent,
            createdAt: start.addingTimeInterval(secondsAfterStart),
            kind: .permission(toolName: "Bash", summary: "npm run build", inputJSON: #"{"command":"npm run build"}"#)
        )
    }

    static let formatQuestion = PendingQuestion(
        header: "Formato",
        question: "Qual formato de feed você quer publicar?",
        options: [
            PendingOption(label: "RSS 2.0", description: "O mais compatível com leitores antigos"),
            PendingOption(label: "Atom", description: "Datas e ids mais rígidos"),
            PendingOption(label: "Os dois", description: "/feed.xml e /atom.xml"),
        ],
        multiSelect: false
    )

    static let testsQuestion = PendingQuestion(
        header: "Testes",
        question: "Quais testes?",
        options: [PendingOption(label: "Unitários"), PendingOption(label: "Integração"), PendingOption(label: "UI")],
        multiSelect: true
    )
}

struct PendingInboxTests {
    @Test func visibleRequestsComeNewestFirstWithTheCount() {
        let inbox = PendingInbox(requests: [
            PendingFixtures.permission("a", agent: "w1:p1", secondsAfterStart: 0),
            PendingFixtures.permission("b", agent: "w2:p1", secondsAfterStart: 30),
            PendingFixtures.permission("c", agent: "w3:p1", secondsAfterStart: 10),
        ])
        #expect(inbox.visible.map(\.id) == ["b", "c", "a"])
        #expect(inbox.count == 3)
    }

    @Test func requestForAgentFindsTheNewestPendingOne() {
        let inbox = PendingInbox(requests: [
            PendingFixtures.permission("old", agent: "w1:p1", secondsAfterStart: 0),
            PendingFixtures.permission("new", agent: "w1:p1", secondsAfterStart: 5),
            PendingFixtures.permission("other", agent: "w2:p1"),
        ])
        #expect(inbox.request(forAgent: "w1:p1")?.id == "new")
        #expect(inbox.request(forAgent: "w9:p9") == nil)
    }

    @Test func anAcceptedAnswerHidesTheRequestUntilTheNextList() {
        var inbox = PendingInbox(requests: [PendingFixtures.permission("a"), PendingFixtures.permission("b", agent: "w2:p1")])
        let first = inbox.beginSending("a")
        let repeated = inbox.beginSending("a")
        #expect(first)
        #expect(!repeated)
        #expect(inbox.isSending("a"))
        inbox.finishSending("a", outcome: .accepted)
        let afterAnswer = inbox.beginSending("a")
        #expect(!afterAnswer)
        #expect(!inbox.isSending("a"))
        #expect(inbox.visible.map(\.id) == ["b"])
        #expect(inbox.request(forAgent: "w1:p1") == nil)
        inbox.replace(with: [PendingFixtures.permission("b", agent: "w2:p1")])
        #expect(inbox.answered.isEmpty)
        #expect(inbox.count == 1)
    }

    @Test func aGoneRequestIsHiddenLikeAnAcceptedOne() {
        var inbox = PendingInbox(requests: [PendingFixtures.permission("a")])
        let began = inbox.beginSending("a")
        inbox.finishSending("a", outcome: .gone)
        #expect(began)
        #expect(inbox.count == 0)
    }

    @Test func aFailureKeepsTheRequestAndIsClearedByTheNextAttempt() {
        var inbox = PendingInbox(requests: [PendingFixtures.permission("a")])
        let first = inbox.beginSending("a")
        inbox.finishSending("a", outcome: .failed("Sem conexão com o Mac"))
        #expect(first)
        #expect(inbox.count == 1)
        #expect(inbox.failure(for: "a") == "Sem conexão com o Mac")
        let retry = inbox.beginSending("a")
        #expect(retry)
        #expect(inbox.failure(for: "a") == nil)
    }

    @Test func aListWithoutTheRequestDropsItsStateEvenMidFlight() {
        var inbox = PendingInbox(requests: [PendingFixtures.permission("a")])
        let began = inbox.beginSending("a")
        inbox.replace(with: [])
        #expect(began)
        #expect(inbox.sending.isEmpty)
        inbox.finishSending("a", outcome: .failed("x"))
        #expect(inbox.failures.isEmpty)
        #expect(inbox.answered.isEmpty)
        #expect(inbox.count == 0)
    }

    @Test func unknownRequestsCannotBeSent() {
        var inbox = PendingInbox()
        let began = inbox.beginSending("missing")
        inbox.finishSending("missing", outcome: .accepted)
        #expect(!began)
        #expect(inbox.answered.isEmpty)
    }
}
