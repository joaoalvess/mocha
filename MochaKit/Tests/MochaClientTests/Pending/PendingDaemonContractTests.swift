import Foundation
import MochaProtocol
import Testing
@testable import MochaClient
@testable import MochaDaemonCore

struct PendingDaemonContractTests {
    private static func hook(_ file: String) throws -> PermissionRequestHook {
        let event = try HookEvent.decode(.permissionRequest, from: Fixtures.data("hooks/\(file)"))
        guard case .permissionRequest(let request) = event else { throw ContractError.notAPermissionRequest }
        return request
    }

    private static func expectedReply(_ file: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Fixtures.data("hooks/\(file)"))
    }

    private static var userInfo: [AnyHashable: Any] { ["agentId": "w1:p1", "requestId": "6f4c0000-0000-4000-8000-000000000002"] }

    @Test func multipleQuestionsAnsweredInTheAppEncodeLikeTheFixture() throws {
        let request = try Self.hook("PermissionRequest.AskUserQuestion.multi.json")
        let kind = PendingRequestFactory.kind(for: request)
        guard case .question(let questions) = kind else { throw ContractError.notAQuestion }
        var draft = PendingAnswerDraft(questions: questions)
        draft.toggle("Vim", inQuestion: 0)
        draft.toggle("Emacs", inQuestion: 0)
        draft.toggle("UI", inQuestion: 1)
        draft.toggle("Unitários", inQuestion: 1)
        draft.toggle("Claro", inQuestion: 2)
        draft.setOtherText("Sépia", inQuestion: 2)
        let response = try #require(draft.response)
        let reply = try PendingHookReply.reply(to: response, kind: kind, toolInput: request.toolInput)
        #expect(reply == (try Self.expectedReply("response.PermissionRequest.AskUserQuestion.multi.json")))
    }

    @Test func singleQuestionAnsweredFromTheNotificationEncodesLikeTheFixture() throws {
        let request = try Self.hook("PermissionRequest.AskUserQuestion.single.json")
        #expect(PushAlertText.pendingCategory(request) == PendingNotificationCategory.question)
        let body = PushAlertText.needsInputBody(request)
        let reply = try #require(PendingNotificationReply(actionIdentifier: PendingNotificationAction.answer, userInfo: Self.userInfo, body: body, text: "SQLite"))
        let hookReply = try PendingHookReply.reply(to: reply.response, kind: PendingRequestFactory.kind(for: request), toolInput: request.toolInput)
        #expect(hookReply == (try Self.expectedReply("response.PermissionRequest.AskUserQuestion.single.json")))
    }

    @Test func permissionActionsEncodeLikeTheFixtures() throws {
        let request = try Self.hook("PermissionRequest.bash.json")
        #expect(PushAlertText.pendingCategory(request) == PendingNotificationCategory.permission)
        let kind = PendingRequestFactory.kind(for: request)
        let allow = try #require(PendingNotificationReply(actionIdentifier: PendingNotificationAction.allow, userInfo: Self.userInfo, body: "", text: nil))
        #expect(try PendingHookReply.reply(to: allow.response, kind: kind, toolInput: request.toolInput) == (try Self.expectedReply("response.PermissionRequest.allow.json")))
        let deny = try #require(PendingNotificationReply(actionIdentifier: PendingNotificationAction.deny, userInfo: Self.userInfo, body: "", text: nil))
        let denied = try PendingHookReply.reply(to: deny.response, kind: kind, toolInput: request.toolInput)
        #expect(denied["hookSpecificOutput"]?["decision"]?["message"]?.stringValue == PendingHookReply.defaultDenyMessage)
    }

    @Test func planActionsEncodeLikeTheFixtureAndShowThePlainFirstLine() throws {
        let request = try Self.hook("PermissionRequest.ExitPlanMode.json")
        #expect(PushAlertText.pendingCategory(request) == PendingNotificationCategory.plan)
        #expect(PushAlertText.needsInputBody(request) == "Criar o arquivo f.txt")
        let kind = PendingRequestFactory.kind(for: request)
        let pending = LiveActivityContentState.Pending(PendingRequest(id: "req-1", agentId: "w1:p1", createdAt: Date(), kind: kind))
        let content = AgentsActivityContent.Pending(requestId: pending.requestId, kind: .permission, toolName: pending.toolName, text: pending.text, options: [])
        #expect(AgentsActivityActions.actions(for: content, agentId: "w1:p1").map(\.title) == ["Negar", "Aprovar"])
        let allow = try #require(PendingNotificationReply(actionIdentifier: PendingNotificationAction.allow, userInfo: Self.userInfo, body: "", text: nil))
        #expect(try PendingHookReply.reply(to: allow.response, kind: kind, toolInput: request.toolInput) == (try Self.expectedReply("response.PermissionRequest.ExitPlanMode.allow.json")))
        let deny = try #require(PendingNotificationReply(actionIdentifier: PendingNotificationAction.deny, userInfo: Self.userInfo, body: "", text: nil))
        #expect(try PendingHookReply.reply(to: deny.response, kind: kind, toolInput: request.toolInput) == PendingHookReply.deny(nil))
    }

    @Test func permissionCardTextFollowsTheDaemonSummary() throws {
        let request = try Self.hook("PermissionRequest.bash.json")
        guard case .permission(let toolName, let summary, let inputJSON) = PendingRequestFactory.kind(for: request) else {
            throw ContractError.notAPermission
        }
        let text = PendingText.permission(toolName: toolName, summary: summary, inputJSON: inputJSON)
        #expect(text.toolName == "Shell")
        #expect(text.showsPrompt)
        #expect(text.detail == summary)
    }

    @Test func categoriesMatchTheDaemon() {
        #expect(PendingNotificationCategory.permission == PushAlertText.permissionCategory)
        #expect(PendingNotificationCategory.question == PushAlertText.questionCategory)
        #expect(PendingNotificationReply.requestIdKey == "requestId")
    }

    private enum ContractError: Error {
        case notAPermissionRequest
        case notAQuestion
        case notAPermission
    }
}
