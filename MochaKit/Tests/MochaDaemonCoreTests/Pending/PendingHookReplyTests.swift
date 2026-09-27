import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite
struct PendingHookReplyTests {
    static func question(_ file: String) throws -> (kind: PendingKind, toolInput: OrderedJSON) {
        let (_, request) = try PendingSample.permissionHook(file)
        return (PendingRequestFactory.kind(for: request), request.toolInput)
    }

    static func permission() throws -> (kind: PendingKind, toolInput: OrderedJSON) {
        try question("PermissionRequest.bash.json")
    }

    static func expectBytes(_ reply: OrderedJSON, match file: String) throws {
        let fixture = try PendingSample.fixture(file)
        #expect(reply == (try OrderedJSON.parse(fixture)))
        #expect(Data(reply.prettyPrinted().utf8) == PendingSample.withoutTrailingNewline(fixture), "\(file)")
    }

    @Test func allowEncodesLikeTheFixture() throws {
        let (kind, toolInput) = try Self.permission()
        try Self.expectBytes(try PendingHookReply.reply(to: .allow, kind: kind, toolInput: toolInput), match: "response.PermissionRequest.allow.json")
    }

    @Test func denyEncodesLikeTheFixtureAndFallsBackToTheDefaultMessage() throws {
        let (kind, toolInput) = try Self.permission()
        let reply = try PendingHookReply.reply(to: .deny(reason: "Negado pelo celular: não crie arquivos agora"), kind: kind, toolInput: toolInput)
        try Self.expectBytes(reply, match: "response.PermissionRequest.deny.json")
        for reason in [nil, "", "  \n"] as [String?] {
            let fallback = try PendingHookReply.reply(to: .deny(reason: reason), kind: kind, toolInput: toolInput)
            #expect(fallback["hookSpecificOutput"]?["decision"]?["message"]?.stringValue == "Negado pelo usuário no iPhone.")
            #expect(fallback["hookSpecificOutput"]?["decision"]?["interrupt"] == nil)
        }
        let (questionKind, questionInput) = try Self.question("PermissionRequest.AskUserQuestion.single.json")
        let deniedQuestion = try PendingHookReply.reply(to: .deny(reason: nil), kind: questionKind, toolInput: questionInput)
        #expect(deniedQuestion == PendingHookReply.deny(nil))
    }

    @Test func singleAnswerEncodesLikeTheFixture() throws {
        let (kind, toolInput) = try Self.question("PermissionRequest.AskUserQuestion.single.json")
        let reply = try PendingHookReply.reply(to: .answers(["Qual banco?": ["SQLite"]]), kind: kind, toolInput: toolInput)
        try Self.expectBytes(reply, match: "response.PermissionRequest.AskUserQuestion.single.json")
    }

    @Test func multipleAnswersFollowTheOptionOrderAndKeepFreeTextAsTyped() throws {
        let (kind, toolInput) = try Self.question("PermissionRequest.AskUserQuestion.multi.json")
        let reply = try PendingHookReply.reply(
            to: .answers(["Qual tema?": ["Sépia"], "Quais testes?": ["UI", "Unitários", "UI"], "Qual editor?": ["Emacs"], "Outra?": ["x"]]),
            kind: kind,
            toolInput: toolInput
        )
        try Self.expectBytes(reply, match: "response.PermissionRequest.AskUserQuestion.multi.json")
        #expect(reply["hookSpecificOutput"]?["decision"]?["updatedInput"]?["questions"] == toolInput["questions"])
    }

    @Test func answerTextJoinsLabelsBeforeFreeTextAndIgnoresBlankEntries() throws {
        let question = PendingQuestion(
            header: "Testes",
            question: "Quais testes?",
            options: [PendingOption(label: "Unitários"), PendingOption(label: "Integração"), PendingOption(label: "UI")],
            multiSelect: true
        )
        #expect(PendingHookReply.answerText(["UI", " fumaça ", "Unitários", ""], for: question) == "Unitários, UI,  fumaça ")
        #expect(PendingHookReply.answerText(["Integração"], for: question) == "Integração")
        #expect(PendingHookReply.answerText([], for: question) == nil)
        #expect(PendingHookReply.answerText(["", "   "], for: question) == nil)
    }

    @Test func aQuestionWithoutAnswerIsInvalid() throws {
        let (kind, toolInput) = try Self.question("PermissionRequest.AskUserQuestion.multi.json")
        let incomplete: [[String: [String]]] = [
            [:],
            ["Qual editor?": ["Vim"], "Quais testes?": ["UI"]],
            ["Qual editor?": ["Vim"], "Quais testes?": [], "Qual tema?": ["Claro"]],
            ["Qual editor?": ["Vim"], "Quais testes?": ["UI"], "Qual tema?": [" "]],
        ]
        for answers in incomplete {
            #expect(throws: PendingRespondError.self) {
                try PendingHookReply.reply(to: .answers(answers), kind: kind, toolInput: toolInput)
            }
        }
        #expect(throws: PendingRespondError.invalidPayload(PendingHookReply.missingAnswer("Qual tema?"))) {
            try PendingHookReply.reply(to: .answers(["Qual editor?": ["Vim"], "Quais testes?": ["UI"]]), kind: kind, toolInput: toolInput)
        }
    }

    @Test func allowOnAQuestionAndAnswersOnAPermissionAreInvalid() throws {
        let (questionKind, questionInput) = try Self.question("PermissionRequest.AskUserQuestion.single.json")
        #expect(throws: PendingRespondError.invalidPayload(PendingHookReply.allowOnQuestion)) {
            try PendingHookReply.reply(to: .allow, kind: questionKind, toolInput: questionInput)
        }
        let (permissionKind, permissionInput) = try Self.permission()
        #expect(throws: PendingRespondError.invalidPayload(PendingHookReply.answersOnPermission)) {
            try PendingHookReply.reply(to: .answers(["Qual banco?": ["SQLite"]]), kind: permissionKind, toolInput: permissionInput)
        }
    }

    @Test func noDecisionIsTheEmptyObjectFixture() throws {
        try Self.expectBytes(PendingHookReply.noDecision, match: "response.empty.json")
    }
}
