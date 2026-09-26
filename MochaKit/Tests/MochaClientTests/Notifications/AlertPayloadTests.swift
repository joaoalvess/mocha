import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct AlertPayloadTests {
    @Test func turnDonePayloadOpensTheAgentChat() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": ["title": "Claude terminou · login-social", "body": "Pronto: o login com a Apple funciona."],
                "sound": "default",
                "thread-id": "w17:p1",
                "category": "TURN_DONE",
            ],
            "agentId": "w17:p1",
            "kind": "turnDone",
            "sentAt": 1_790_381_218_000,
        ]
        let payload = try #require(AlertPayload(userInfo: userInfo))
        #expect(payload.agentId == "w17:p1")
        #expect(payload.deepLink == .agent("w17:p1"))
        #expect(payload.deepLink.url?.absoluteString == "mocha://agent/w17%3Ap1")
    }

    @Test func needsInputPayloadOpensTheAgentChat() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": ["title": "Claude precisa de você · site-pessoal", "body": "Shell quer rodar npm run build"],
                "category": "NEEDS_INPUT",
                "interruption-level": "time-sensitive",
            ],
            "agentId": "w3:p2",
            "kind": "needsInput",
            "requestId": "req-1",
            "sentAt": 1_790_381_218_000,
        ]
        #expect(AlertPayload(userInfo: userInfo)?.deepLink == .agent("w3:p2"))
    }

    @Test(arguments: [
        #"{}"#,
        #"{"agentId":""}"#,
        #"{"agentId":17}"#,
        #"{"aps":{"alert":"Mocha"}}"#,
    ])
    func payloadWithoutAgentIsIgnored(_ json: String) throws {
        let userInfo = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [AnyHashable: Any])
        #expect(AlertPayload(userInfo: userInfo) == nil)
    }

    @Test func categoriesMatchTheSpec() {
        #expect(AlertCategory.turnDone == "TURN_DONE")
        #expect(AlertCategory.needsInput == "NEEDS_INPUT")
        #expect(AlertCategory.all == ["TURN_DONE", "NEEDS_INPUT"])
    }
}
