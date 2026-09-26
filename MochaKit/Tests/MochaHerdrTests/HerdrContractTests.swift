import Foundation
import MochaTestSupport
import Testing
@testable import MochaHerdr

@Suite(.timeLimit(.minutes(1)))
struct HerdrContractTests {
    private static let sampleRequests: [HerdrRequest] = [
        .ping,
        .sessionSnapshot,
        .agentList,
        .agentGet(target: "w1A:p1"),
        .workspaceList,
        .tabList(workspaceId: nil),
        .tabList(workspaceId: "w1A"),
        .paneGet(paneId: "w1A:p2"),
        .agentPrompt(target: "w1A:p1", text: "Responda apenas com a palavra: pronto"),
        .agentSendKeys(target: "w1A:p1", keys: ["Escape"]),
        .eventsSubscribe(HerdrSubscription.globalLifecycle),
        .eventsSubscribe([.agentStatusChanged(paneId: "w1A:p1")]),
    ]

    private func send(_ request: HerdrRequest, with client: HerdrClient) async throws {
        switch request {
        case .ping:
            _ = try await client.ping()
        case .sessionSnapshot:
            _ = try await client.sessionSnapshot()
        case .agentList:
            _ = try await client.agentList()
        case .agentGet(let target):
            _ = try await client.agentGet(target: target)
        case .workspaceList:
            _ = try await client.workspaceList()
        case .tabList(let workspaceId):
            _ = try await client.tabList(workspaceId: workspaceId)
        case .paneGet(let paneId):
            _ = try await client.paneGet(paneId: paneId)
        case .agentPrompt(let target, let text):
            _ = try await client.agentPrompt(target: target, text: text)
        case .agentSendKeys(let target, let keys):
            try await client.agentSendKeys(target: target, keys: keys)
        case .eventsSubscribe(let subscriptions):
            try await client.subscribe(subscriptions).cancel()
        }
    }

    @Test func everyRequestTheClientSendsExistsInTheSchema() async throws {
        let schema = try HerdrSchemaValidator.load()
        try await withFakeHerdr { server, client in
            for request in Self.sampleRequests {
                try await send(request, with: client)
            }
            let recorded = await server.requests
            #expect(recorded.count == Self.sampleRequests.count)
            #expect(Set(recorded.map(\.method)) == Set(Self.sampleRequests.map(\.method)))
            for request in recorded {
                #expect(schema.requestViolations(request.line) == [], "\(request.method)")
            }
        }
    }

    @Test func encodedRequestsValidateStrictly() throws {
        let schema = try HerdrSchemaValidator.load()
        for request in Self.sampleRequests {
            #expect(schema.requestViolations(try request.encodedLine(id: "c1")) == [], "\(request.method)")
        }
        #expect(schema.requestMethods.contains("session.snapshot"))
        #expect(Set(HerdrGlobalEventType.allCases.map(\.rawValue)).isSubset(of: schema.subscriptionTypes))
        #expect(schema.subscriptionTypes.contains(HerdrSubscription.agentStatusChangedType))
    }

    @Test func validatorRejectsWhatTheHerdrWouldSilentlyIgnore() throws {
        let schema = try HerdrSchemaValidator.load()
        let wrongSplit = Data(#"{"id":"r1","method":"pane.split","params":{"pane_id":"w1A:p1","direction":"right"}}"#.utf8)
        #expect(schema.requestViolations(wrongSplit).contains { $0.contains("unknown field pane_id") })
        let rightSplit = Data(#"{"id":"r1","method":"pane.split","params":{"target_pane_id":"w1A:p1","direction":"right"}}"#.utf8)
        #expect(!schema.requestViolations(rightSplit).contains { $0.contains("unknown field") })
        #expect(!schema.requestViolations(Data(#"{"id":"r1","method":"agent.get","params":{}}"#.utf8)).isEmpty)
        #expect(!schema.requestViolations(Data(#"{"id":"r1","method":"nope.nope","params":{}}"#.utf8)).isEmpty)
        #expect(!schema.requestViolations(Data(#"{"id":7,"method":"ping","params":{}}"#.utf8)).isEmpty)
        #expect(!schema.requestViolations(Data(#"{"id":"r1","method":"ping"}"#.utf8)).isEmpty)
        #expect(!schema.requestViolations(Data(#"{"id":"r1","method":"ping","params":{"extra":1}}"#.utf8)).isEmpty)
        let globalWithPane = Data(#"{"id":"s","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.updated","pane_id":"w1A:p1"}]}}"#.utf8)
        #expect(!schema.requestViolations(globalWithPane).isEmpty)
    }

    @Test func fixturesValidateAgainstTheSchema() throws {
        let schema = try HerdrSchemaValidator.load()
        for name in try HerdrFixtures.allNames() {
            if name.hasSuffix(".jsonl") {
                for line in try HerdrFixtures.lines(name) {
                    let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
                    let section: HerdrSchemaValidator.Section =
                        object["result"] != nil ? .successResponse : (object["event"] as? String)?.contains(".") == true ? .subscriptionEvent : .event
                    #expect(schema.violations(of: line, section: section) == [], "\(name)")
                }
                continue
            }
            guard name.hasSuffix(".json"), name != "herdr-api.schema.json" else { continue }
            let data = try HerdrFixtures.data(name)
            if name.hasSuffix(".request.json") {
                #expect(schema.requestViolations(data) == [], "\(name)")
            } else if name.hasPrefix("event.pane.") {
                #expect(schema.violations(of: data, section: .subscriptionEvent) == [], "\(name)")
            } else if name.hasPrefix("event.") {
                #expect(schema.violations(of: data, section: .event) == [], "\(name)")
            } else if name.hasPrefix("error.") {
                #expect(schema.violations(of: data, section: .errorResponse) == [], "\(name)")
            } else {
                #expect(schema.violations(of: data, section: .successResponse) == [], "\(name)")
            }
        }
    }

    @Test func syntheticSnapshotIsCheckedByTheValidator() throws {
        let schema = try HerdrSchemaValidator.load()
        let valid = try HerdrFixtures.data("session.snapshot.linked-worktree.synthetic.json")
        #expect(schema.violations(of: valid, section: .successResponse) == [])
        var object = try #require(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var result = try #require(object["result"] as? [String: Any])
        var snapshot = try #require(result["snapshot"] as? [String: Any])
        snapshot["panes"] = [["pane_id": "w5:p1"]]
        result["snapshot"] = snapshot
        object["result"] = result
        let broken = try JSONSerialization.data(withJSONObject: object)
        #expect(!schema.violations(of: broken, section: .successResponse).isEmpty)
    }
}
