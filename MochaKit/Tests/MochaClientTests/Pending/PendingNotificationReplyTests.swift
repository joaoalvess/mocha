import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct PendingNotificationReplyTests {
    private static var userInfo: [AnyHashable: Any] {
        [
            "aps": [
                "alert": ["title": "Claude precisa de você · site-pessoal", "body": "npm run build"],
                "category": "PERMISSION",
                "interruption-level": "time-sensitive",
            ],
            "agentId": "w3:p2",
            "kind": "needsInput",
            "requestId": "5e3b0000-0000-4000-8000-000000000001",
            "sentAt": 1_790_381_218_000,
        ]
    }

    @Test func allowAndDenyCarryTheRequestAndAgent() throws {
        let allow = try #require(PendingNotificationReply(actionIdentifier: "ALLOW", userInfo: Self.userInfo, body: "npm run build", text: nil))
        #expect(allow == PendingNotificationReply(requestId: "5e3b0000-0000-4000-8000-000000000001", agentId: "w3:p2", response: .allow))
        let deny = try #require(PendingNotificationReply(actionIdentifier: "DENY", userInfo: Self.userInfo, body: "npm run build", text: nil))
        #expect(deny.response == .deny(reason: nil))
    }

    @Test func answerUsesTheQuestionFromTheBodyAndTheTypedText() throws {
        let reply = try #require(PendingNotificationReply(actionIdentifier: "ANSWER", userInfo: Self.userInfo, body: "Qual banco?", text: "  SQLite\n"))
        #expect(reply.response == .answers(["Qual banco?": ["SQLite"]]))
    }

    @Test(arguments: [nil, "", "  \n"] as [String?])
    func blankAnswerIsIgnored(_ text: String?) {
        #expect(PendingNotificationReply(actionIdentifier: "ANSWER", userInfo: Self.userInfo, body: "Qual banco?", text: text) == nil)
    }

    @Test func answerWithoutQuestionIsIgnored() {
        #expect(PendingNotificationReply(actionIdentifier: "ANSWER", userInfo: Self.userInfo, body: "", text: "SQLite") == nil)
    }

    @Test func otherActionsAreNotReplies() {
        #expect(PendingNotificationReply(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: Self.userInfo, body: "x", text: nil) == nil)
        #expect(PendingNotificationReply(actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier", userInfo: Self.userInfo, body: "x", text: nil) == nil)
    }

    @Test func payloadWithoutRequestIsNotAReply() {
        var userInfo = Self.userInfo
        userInfo["requestId"] = nil
        #expect(PendingNotificationReply(actionIdentifier: "ALLOW", userInfo: userInfo, body: "x", text: nil) == nil)
        userInfo["requestId"] = ""
        #expect(PendingNotificationReply(actionIdentifier: "ALLOW", userInfo: userInfo, body: "x", text: nil) == nil)
    }

    @Test func missingAgentStillReplies() throws {
        var userInfo = Self.userInfo
        userInfo["agentId"] = nil
        let reply = try #require(PendingNotificationReply(actionIdentifier: "DENY", userInfo: userInfo, body: "x", text: nil))
        #expect(reply.agentId == nil)
    }

    @Test func identifiersMatchTheSpec() {
        #expect(PendingNotificationCategory.permission == "PERMISSION")
        #expect(PendingNotificationCategory.question == "QUESTION")
        #expect(PendingNotificationCategory.all == ["PERMISSION", "QUESTION"])
        #expect(Set(PendingNotificationCategory.all).isDisjoint(with: AlertCategory.all))
        #expect(Set([PendingNotificationAction.allow, PendingNotificationAction.deny, PendingNotificationAction.answer]).count == 3)
    }
}
