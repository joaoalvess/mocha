import Foundation
import Testing
@testable import MochaDaemonCore

struct ApnsPayloadTests {
    private let sentAt = Date(timeIntervalSince1970: 1_790_000_000.123)

    private var state: AgentActivityContentState {
        AgentActivityContentState(
            agent: .init(
                agentId: "w17:p1",
                title: "roda os testes",
                workspaceLabel: "demo-app",
                status: "blocked",
                since: Date(timeIntervalSince1970: 1_789_999_900)
            ),
            pending: nil,
            updatedAt: sentAt
        )
    }

    @Test func alertPayloadMatchesSpecShape() throws {
        let push = ApnsAlertPush(
            title: "Claude terminou · demo-app",
            body: "Pronto.",
            threadId: "w17:p1",
            category: "TURN_DONE",
            agentId: "w17:p1",
            kind: "turnDone",
            sentAt: sentAt
        )
        let object = try PushTestData.jsonObject(try push.payload())
        let aps = try #require(object["aps"] as? [String: Any])
        let alert = try #require(aps["alert"] as? [String: Any])
        #expect(alert["title"] as? String == "Claude terminou · demo-app")
        #expect(alert["body"] as? String == "Pronto.")
        #expect(aps["sound"] as? String == "default")
        #expect(aps["thread-id"] as? String == "w17:p1")
        #expect(aps["category"] as? String == "TURN_DONE")
        #expect(aps["interruption-level"] == nil)
        #expect(object["agentId"] as? String == "w17:p1")
        #expect(object["kind"] as? String == "turnDone")
        #expect(object["requestId"] == nil)
        #expect(object["sentAt"] as? Int64 == 1_790_000_000_123)
    }

    @Test func timeSensitiveAlertCarriesInterruptionLevel() throws {
        let push = ApnsAlertPush(
            title: "Claude precisa de você · demo-app",
            body: "rm -rf build",
            interruptionLevel: .timeSensitive,
            kind: "needsInput",
            requestId: "5e3b",
            sentAt: sentAt
        )
        let object = try PushTestData.jsonObject(try push.payload())
        let aps = try #require(object["aps"] as? [String: Any])
        #expect(aps["interruption-level"] as? String == "time-sensitive")
        #expect(object["requestId"] as? String == "5e3b")
    }

    @Test func contentStateEncodesDatesAsSecondsSinceReferenceDate() throws {
        let object = try PushTestData.jsonObject(try JSONEncoder().encode(state))
        #expect(object["updatedAt"] as? Double == sentAt.timeIntervalSinceReferenceDate)
        #expect(object["since"] as? Double == Date(timeIntervalSince1970: 1_789_999_900).timeIntervalSinceReferenceDate)
        let plain = JSONEncoder()
        plain.outputFormatting = [.sortedKeys]
        let iso = JSONEncoder()
        iso.outputFormatting = [.sortedKeys]
        iso.dateEncodingStrategy = .iso8601
        #expect(try plain.encode(state) == iso.encode(state))
    }

    @Test func contentStateFlattensTheAgentAndDecodesWithDefaultDecoderLikeActivityKit() throws {
        let object = try PushTestData.jsonObject(try JSONEncoder().encode(state))
        #expect(Set(object.keys) == ["agentId", "title", "workspaceLabel", "status", "since", "updatedAt"])
        let decoded = try JSONDecoder().decode(LiveActivityAppContentState.self, from: try JSONEncoder().encode(state))
        #expect(decoded == LiveActivityAppContentState(
            status: "blocked",
            title: "roda os testes",
            workspaceLabel: "demo-app",
            since: Date(timeIntervalSince1970: 1_789_999_900),
            updatedAt: sentAt
        ))
    }

    @Test func updatePayloadHasEventTimestampContentStateAndRelevance() throws {
        let push = AgentActivityPush(
            agentId: "w17:p1",
            event: .update(alert: nil),
            contentState: state,
            timestamp: sentAt,
            staleDate: Date(timeIntervalSince1970: 1_790_000_900),
            relevanceScore: 100
        )
        let aps = try #require(try PushTestData.jsonObject(try push.payload())["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "update")
        #expect(aps["timestamp"] as? Int64 == 1_790_000_000)
        #expect(aps["stale-date"] as? Int64 == 1_790_000_900)
        #expect(aps["relevance-score"] as? Double == 100)
        #expect(aps["content-state"] is [String: Any])
        #expect(Set(aps.keys) == ["event", "timestamp", "stale-date", "relevance-score", "content-state"])
    }

    @Test func anUpdateCanCarryAnAlertWithSound() throws {
        let push = AgentActivityPush(
            agentId: "w17:p1",
            event: .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "rm -rf build")),
            contentState: state,
            timestamp: sentAt
        )
        let aps = try #require(try PushTestData.jsonObject(try push.payload())["aps"] as? [String: Any])
        let alert = try #require(aps["alert"] as? [String: Any])
        #expect(alert["title"] as? String == "Claude precisa de você · demo-app")
        #expect(alert["body"] as? String == "rm -rf build")
        #expect(alert["sound"] as? String == "default")
        #expect(aps["attributes-type"] == nil)
        #expect(aps["input-push-token"] == nil)
    }

    @Test func startPayloadHasTheAgentAttributesAlertAndInputPushToken() throws {
        let push = AgentActivityPush(
            agentId: "w17:p1",
            event: .start(alert: AgentActivityAlert(title: "Claude trabalhando · demo-app", body: "roda os testes", sound: nil)),
            contentState: state,
            timestamp: sentAt
        )
        let aps = try #require(try PushTestData.jsonObject(try push.payload())["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "start")
        #expect(aps["attributes-type"] as? String == "MochaAgentAttributes")
        #expect(aps["attributes"] as? [String: String] == ["agentId": "w17:p1"])
        #expect(aps["input-push-token"] as? Int == 1)
        let alert = try #require(aps["alert"] as? [String: Any])
        #expect(alert["title"] as? String == "Claude trabalhando · demo-app")
        #expect(alert["body"] as? String == "roda os testes")
        #expect(alert["sound"] == nil)
        #expect(aps["dismissal-date"] == nil)
    }

    @Test func endPayloadHasDismissalDate() throws {
        let push = AgentActivityPush(
            agentId: "w17:p1",
            event: .end(dismissalDate: Date(timeIntervalSince1970: 1_790_000_900)),
            contentState: state,
            timestamp: sentAt
        )
        let aps = try #require(try PushTestData.jsonObject(try push.payload())["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "end")
        #expect(aps["dismissal-date"] as? Int64 == 1_790_000_900)
        #expect(aps["attributes-type"] == nil)
        #expect(aps["alert"] == nil)
    }

    @Test func liveActivityPayloadFitsInFourKilobytesWithLongTitle() throws {
        var longState = state
        longState.agent.title = String(repeating: "título longo ", count: 5)
        let push = AgentActivityPush(agentId: "w17:p1", event: .start(alert: .init(title: "Mocha", body: "texto")), contentState: longState, timestamp: sentAt)
        #expect(push.fitsPayloadLimit)
        #expect(try push.payload().count < ApnsRequest.maxPayloadBytes)
    }
}
