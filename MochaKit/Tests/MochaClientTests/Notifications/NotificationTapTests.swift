import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

@MainActor
struct NotificationTapTests {
    @Test func tapBeforeTheSessionStartsIsDeliveredWhenItAttaches() {
        let relay = NotificationTapRelay()
        relay.deliver(.agent("w17:p1"))
        var received: [DeepLink] = []
        relay.attach { received.append($0) }
        #expect(received == [.agent("w17:p1")])
    }

    @Test func onlyTheLatestTapBeforeTheSessionStartsIsKept() {
        let relay = NotificationTapRelay()
        relay.deliver(.agent("w1:p1"))
        relay.deliver(.agent("w2:p1"))
        var received: [DeepLink] = []
        relay.attach { received.append($0) }
        #expect(received == [.agent("w2:p1")])
    }

    @Test func tapsAfterTheSessionStartsAreDeliveredRightAway() {
        let relay = NotificationTapRelay()
        var received: [DeepLink] = []
        relay.attach { received.append($0) }
        #expect(received.isEmpty)
        relay.deliver(.agent("w1:p1"))
        relay.deliver(.agent("w2:p1"))
        #expect(received == [.agent("w1:p1"), .agent("w2:p1")])
    }

    @Test func tapWithTheAppClosedOpensTheChatOverHome() {
        let step = ChatNavigation.open(.agent("w17:p1"), stack: [])
        #expect(step == .show(path: [.agent("w17:p1")], closing: []))
    }

    @Test func tapWithAnotherChatOpenReplacesIt() {
        let step = ChatNavigation.open(.agent("w17:p1"), stack: [ChatStackEntry(route: .agent("w3:p2"), target: .agent("w3:p2"))])
        #expect(step == .show(path: [.agent("w17:p1")], closing: [.agent("w3:p2")]))
    }

    @Test func tapWithAnArchivedSessionOpenReplacesIt() {
        let session = ChatTarget.session("9d1c1e4a-2b7f-4f3e-9d51-0a4c9b0f6c11")
        let step = ChatNavigation.open(.agent("w17:p1"), stack: [ChatStackEntry(route: session, target: session)])
        #expect(step == .show(path: [.agent("w17:p1")], closing: [session]))
    }

    @Test func tapForTheVisibleChatKeepsIt() {
        let step = ChatNavigation.open(.agent("w17:p1"), stack: [ChatStackEntry(route: .agent("w17:p1"), target: .agent("w17:p1"))])
        #expect(step == .stay)
    }

    @Test func tapWithTheOldIdOfTheVisibleChatKeepsIt() {
        #expect(ChatNavigation.open(.agent("w1:p1"), stack: [ChatStackEntry(route: .agent("w1:p1"), target: .agent("w9:p4"))]) == .stay)
        #expect(ChatNavigation.open(.agent("w9:p4"), stack: [ChatStackEntry(route: .agent("w1:p1"), target: .agent("w9:p4"))]) == .stay)
    }

    @Test func tapPayloadGoesThroughTheRelayAsADeepLink() throws {
        let relay = NotificationTapRelay()
        let payload = try #require(AlertPayload(userInfo: ["agentId": "w17:p1", "kind": "turnDone"]))
        relay.deliver(payload.deepLink)
        var opened: [ChatNavigationStep] = []
        relay.attach { link in
            guard case .agent(let agentId) = link else { return }
            opened.append(ChatNavigation.open(.agent(agentId), stack: [ChatStackEntry(route: .agent("w3:p2"), target: .agent("w3:p2"))]))
        }
        #expect(opened == [.show(path: [.agent("w17:p1")], closing: [.agent("w3:p2")])])
    }
}
