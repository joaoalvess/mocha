import Foundation
import MochaTestSupport
import Testing
@testable import MochaHerdr

@Suite struct HerdrRequestTests {
    private func line(_ request: HerdrRequest, id: String = "r1") throws -> String {
        String(decoding: try request.encodedLine(id: id), as: UTF8.self)
    }

    @Test func requestsAreSingleLinesWithStringIdAndParams() throws {
        #expect(try line(.ping) == #"{"id":"r1","method":"ping","params":{}}"# + "\n")
        #expect(try line(.sessionSnapshot) == #"{"id":"r1","method":"session.snapshot","params":{}}"# + "\n")
        #expect(try line(.agentList) == #"{"id":"r1","method":"agent.list","params":{}}"# + "\n")
        #expect(try line(.agentGet(target: "w1A:p1")) == #"{"id":"r1","method":"agent.get","params":{"target":"w1A:p1"}}"# + "\n")
        #expect(try line(.tabList(workspaceId: nil)) == #"{"id":"r1","method":"tab.list","params":{}}"# + "\n")
        #expect(try line(.tabList(workspaceId: "w1A")) == #"{"id":"r1","method":"tab.list","params":{"workspace_id":"w1A"}}"# + "\n")
        #expect(try line(.paneGet(paneId: "w1A:p2")) == #"{"id":"r1","method":"pane.get","params":{"pane_id":"w1A:p2"}}"# + "\n")
        #expect(
            try line(.agentPrompt(target: "w1A:p1", text: "olá\n/clear"))
                == #"{"id":"r1","method":"agent.prompt","params":{"target":"w1A:p1","text":"olá\n/clear"}}"# + "\n"
        )
        #expect(
            try line(.agentSendKeys(target: "w1A:p1", keys: ["Escape"]))
                == #"{"id":"r1","method":"agent.send_keys","params":{"keys":["Escape"],"target":"w1A:p1"}}"# + "\n"
        )
    }

    @Test func subscriptionRequestMatchesTheFixture() throws {
        let request = HerdrRequest.eventsSubscribe(HerdrSubscription.globalLifecycle + [.agentStatusChanged(paneId: "w1A:p1")])
        let encoded = try jsonObject(request.encodedLine(id: "sub1"))
        let fixture = try jsonObject(HerdrFixtures.data("events.subscribe.request.json"))
        #expect(encoded == fixture)
    }

    @Test func globalSubscriptionsFollowTheSpec() {
        #expect(HerdrSubscription.globalLifecycle.count == 19)
        #expect(!HerdrGlobalEventType.allCases.contains { $0.rawValue.hasSuffix("focused") })
        #expect(!HerdrGlobalEventType.allCases.map(\.rawValue).contains("layout.updated"))
        #expect(!HerdrGlobalEventType.allCases.map(\.rawValue).contains("workspace.metadata_updated"))
        #expect(HerdrGlobalEventType.paneAgentDetected.wireEventName == "pane_agent_detected")
        #expect(HerdrGlobalEventType.workspaceCreated.wireEventName == "workspace_created")
    }

    @Test func socketPathFollowsResolutionOrder() {
        let home = URL(filePath: "/Users/dev", directoryHint: .isDirectory)
        let environment = ["HERDR_SOCKET_PATH": "/tmp/pane.sock", "HERDR_SESSION": "work"]
        #expect(HerdrSocketPath.resolve(override: "/tmp/override.sock", environment: environment, homeDirectory: home) == "/tmp/override.sock")
        #expect(HerdrSocketPath.resolve(environment: environment, homeDirectory: home) == "/tmp/pane.sock")
        #expect(
            HerdrSocketPath.resolve(environment: ["HERDR_SESSION": "work"], homeDirectory: home)
                == "/Users/dev/.config/herdr/sessions/work/herdr.sock"
        )
        #expect(HerdrSocketPath.resolve(environment: [:], homeDirectory: home) == "/Users/dev/.config/herdr/herdr.sock")
        #expect(HerdrSocketPath.resolve(override: "", environment: ["HERDR_SOCKET_PATH": ""], homeDirectory: home) == "/Users/dev/.config/herdr/herdr.sock")
    }
}
