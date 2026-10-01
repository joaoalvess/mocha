import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct AgentsActivityActionsTests {
    private static func pending(kind: AgentsActivityContent.Pending.Kind, text: String, options: [String] = [], toolName: String? = nil) -> AgentsActivityContent.Pending {
        AgentsActivityContent.Pending(requestId: "req-1", kind: kind, toolName: toolName, text: text, options: options)
    }

    @Test func permissionOffersDenyThenAllow() {
        let actions = AgentsActivityActions.actions(for: Self.pending(kind: .permission, text: "npm run build", toolName: "Bash"), agentId: "w17:p1")
        #expect(actions == [
            AgentsActivityAction(requestId: "req-1", agentId: "w17:p1", role: .deny, title: "Negar", choice: .deny),
            AgentsActivityAction(requestId: "req-1", agentId: "w17:p1", role: .allow, title: "Permitir", choice: .allow),
        ])
        #expect(actions.map(\.choice.response) == [.deny(reason: nil), .allow])
    }

    @Test func planOffersDenyThenApprove() {
        let actions = AgentsActivityActions.actions(for: Self.pending(kind: .permission, text: "Criar o arquivo f.txt", toolName: "ExitPlanMode"), agentId: "w17:p1")
        #expect(actions == [
            AgentsActivityAction(requestId: "req-1", agentId: "w17:p1", role: .deny, title: "Negar", choice: .deny),
            AgentsActivityAction(requestId: "req-1", agentId: "w17:p1", role: .allow, title: "Aprovar", choice: .allow),
        ])
    }

    @Test func questionWithOptionsAnswersWithTheExactQuestionAndLabel() {
        let question = "Qual formato de feed você quer publicar? "
        let actions = AgentsActivityActions.actions(for: Self.pending(kind: .question, text: question, options: ["RSS 2.0", " Atom", "Os dois"]), agentId: "w17:p1")
        #expect(actions.map(\.title) == ["RSS 2.0", " Atom", "Os dois"])
        #expect(actions.allSatisfy { $0.role == .option && $0.requestId == "req-1" && $0.agentId == "w17:p1" })
        #expect(actions.map(\.choice.response) == [
            .answers([question: ["RSS 2.0"]]),
            .answers([question: [" Atom"]]),
            .answers([question: ["Os dois"]]),
        ])
    }

    @Test func codexQuestionAnswersWithTheQuestionTextLikeClaude() {
        let question = "Qual cache usar em /receitas?"
        let actions = AgentsActivityActions.actions(for: Self.pending(kind: .question, text: question, options: ["Redis", "Memória"]), agentId: "w3:p5")
        #expect(actions.map(\.title) == ["Redis", "Memória"])
        #expect(actions.allSatisfy { $0.agentId == "w3:p5" && $0.role == .option })
        #expect(actions.map(\.choice.response) == [.answers([question: ["Redis"]]), .answers([question: ["Memória"]])])
        #expect(actions.map(\.choice.outcome) == [.answered, .answered])
    }

    @Test func codexCommandApprovalOffersDenyThenAllow() {
        let actions = AgentsActivityActions.actions(for: Self.pending(kind: .permission, text: "go test ./...", toolName: "Shell"), agentId: "w3:p6")
        #expect(actions.map(\.title) == ["Negar", "Permitir"])
        #expect(actions.map(\.choice.response) == [.deny(reason: nil), .allow])
    }

    @Test(arguments: [1, 4])
    func questionOptionsUpToTheLimitAreOffered(count: Int) {
        let options = (1...count).map { "Opção \($0)" }
        #expect(AgentsActivityActions.actions(for: Self.pending(kind: .question, text: "Qual?", options: options), agentId: "w17:p1").count == count)
    }

    @Test func questionWithoutInlineAnswerHasNoButtons() {
        #expect(AgentsActivityActions.actions(for: Self.pending(kind: .question, text: "Prévia da pergunta…"), agentId: "w17:p1").isEmpty)
        #expect(AgentsActivityActions.actions(for: Self.pending(kind: .question, text: "Qual?", options: ["a", "b", "c", "d", "e"]), agentId: "w17:p1").isEmpty)
        #expect(AgentsActivityActions.actions(for: Self.pending(kind: .question, text: "", options: ["a"]), agentId: "w17:p1").isEmpty)
    }

    @Test(arguments: [
        ("protocol/pendingResponse.allow.json", AgentsActivityChoice.allow),
        ("protocol/pendingResponse.deny.noReason.json", .deny),
        ("protocol/pendingResponse.answers.json", .answer(question: "Qual formato?", label: "JSON")),
    ])
    func choiceEncodesLikeTheProtocolFixture(fixture: String, choice: AgentsActivityChoice) throws {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(choice.response)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Fixtures.data(fixture)) as? NSDictionary
        #expect(encoded == expected)
    }

    @Test(arguments: [
        (PendingRespondResult.accepted, true),
        (.gone, true),
        (.refused, false),
        (.unauthorized, false),
        (.notPaired, false),
        (.unreachable, false),
        (.unexpectedStatus(502), false),
    ])
    func onlyAnAcceptedOrAlreadyAnsweredRequestLeavesTheActivity(result: PendingRespondResult, clears: Bool) {
        #expect(AgentsActivityReply.clearsPending(after: result) == clears)
    }

    @Test func refusedAndUnreachableRepliesShowTheNotificationNotice() {
        #expect(PendingText.failureNotice(for: .gone)?.title == "Esse pedido já foi resolvido no Mac")
        #expect(PendingText.failureNotice(for: .refused)?.title == "O Mac recusou a resposta")
        #expect(PendingText.failureNotice(for: .unreachable)?.title == "Não consegui falar com o Mac")
    }
}
