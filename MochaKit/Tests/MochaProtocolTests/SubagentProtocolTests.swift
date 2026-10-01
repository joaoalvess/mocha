import Foundation
import Testing
@testable import MochaProtocol

private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(json.utf8))
}

private func encodedJSON<Value: Encodable>(_ value: Value) throws -> JSONValue {
    try JSONValue(data: JSONEncoder().encode(value))
}

private let sessionId = "0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64"
private let subagentId = "a0123456789abcdef"
private let sessionField = #""sessionId":""# + sessionId + #"""#
private let subagentField = #""subagentId":""# + subagentId + #"""#

private func chatTarget(of name: String) throws -> ChatTarget? {
    let data = try ProtocolFixtures.data(name)
    if name.hasPrefix("client.") {
        switch try JSONDecoder().decode(ClientEnvelope.self, from: data).message {
        case .openChat(let target, _, _), .closeChat(let target): return target
        default: return nil
        }
    }
    switch try JSONDecoder().decode(ServerEnvelope.self, from: data).message {
    case .chatPage(let page): return page.target
    case .chatAppend(let target, _), .chatUpdate(let target, _), .chatMeta(let target, _): return target
    default: return nil
    }
}

private func chatUpdateItems(_ items: String) throws -> [ChatItem] {
    let envelope = try decode(
        ServerEnvelope.self,
        #"{"v":1,"type":"chatUpdate","payload":{"agentId":"w1:p1","items":"# + items + "}}"
    )
    guard case .chatUpdate(_, let decoded) = envelope.message else {
        Issue.record("esperava chatUpdate")
        return []
    }
    return decoded
}

@Suite struct SubagentTargetCodingTests {
    @Test(arguments: TargetedMessage.all)
    func sessionWithSubagentIdDecodesAsSubagent(_ message: TargetedMessage) throws {
        let target = try message.decodedTarget(targetFields: sessionField + "," + subagentField)
        #expect(target == .subagent(sessionId: sessionId, agentId: subagentId))
    }

    @Test(arguments: TargetedMessage.all)
    func subagentIdWithoutSessionIdThrows(_ message: TargetedMessage) {
        #expect(throws: DecodingError.self) {
            try message.decodedTarget(targetFields: subagentField)
        }
        #expect(throws: DecodingError.self) {
            try message.decodedTarget(targetFields: #""agentId":"w1:p1","# + subagentField)
        }
        #expect(throws: DecodingError.self) {
            try message.decodedTarget(targetFields: #""agentId":"w1:p1","# + sessionField + "," + subagentField)
        }
    }

    @Test func subagentTargetIsFlattenedIntoThePayload() throws {
        let target = ChatTarget.subagent(sessionId: sessionId, agentId: subagentId)
        let open = ClientEnvelope(id: "c-1", message: .openChat(target: target, limit: 60))
        #expect(try encodedJSON(open)["payload"] == .object([
            "sessionId": .string(sessionId), "subagentId": .string(subagentId), "limit": .number(60),
        ]))

        let meta = ChatMeta(title: "t", workspaceLabel: "w", status: .unknown)
        let page = ChatPage(target: target, meta: meta, items: [], before: nil, hasMore: false)
        let pageJSON = try encodedJSON(page)
        #expect(pageJSON["sessionId"] == .string(sessionId))
        #expect(pageJSON["subagentId"] == .string(subagentId))
        #expect(pageJSON["agentId"] == nil)

        let session = ClientEnvelope(id: "c-2", message: .closeChat(target: .session(sessionId)))
        #expect(try encodedJSON(session)["payload"]?["subagentId"] == nil)
    }

    @Test(arguments: ProtocolFixtures.names.filter { $0.hasSuffix(".subagent.json") })
    func subagentFixturesUseTheSubagentTarget(_ name: String) throws {
        guard case .subagent = try chatTarget(of: name) else {
            Issue.record("\(name) deveria usar ChatTarget.subagent")
            return
        }
    }

    @Test func agentOnlyMessagesRejectASubagentTarget() {
        for type in ["sendPrompt", "interrupt", "closeAgent", "slash", "listSubagents"] {
            #expect(throws: DecodingError.self, "\(type)") {
                try decode(
                    ClientEnvelope.self,
                    #"{"v":1,"id":"c-1","type":""# + type + #"","payload":{"# + sessionField + "," + subagentField + "}}"
                )
            }
        }
    }
}

@Suite struct SubagentMessageTests {
    @Test func listSubagentsCarriesTheAgentId() throws {
        let envelope = try decode(ClientEnvelope.self, #"{"v":1,"id":"c-13","type":"listSubagents","payload":{"agentId":"w17:p1"}}"#)
        #expect(envelope.message == .listSubagents(agentId: "w17:p1"))
        #expect(try encodedJSON(envelope)["payload"] == .object(["agentId": .string("w17:p1")]))
    }

    @Test func subagentListDropsInvalidItemsAndKeepsTheOthers() throws {
        let json = """
        {"v":1,"id":"c-13","type":"subagentList","payload":{"agentId":"w17:p1","items":[
          {"agentId":"a1","agentType":"Explore","description":"ok","status":"running","toolUses":1},
          {"agentId":"a2","agentType":"Explore","description":"estado novo","status":"paused","toolUses":1},
          {"agentId":"a3","agentType":"Explore","description":"sem contagem","status":"completed"},
          {"agentId":"a4","agentType":"Explore","description":"data ruim","status":"completed","toolUses":2,"startedAt":"ontem"},
          "solto",
          {"agentId":"a5","parentAgentId":"a1","agentType":"Plan","description":"aninhado","status":"stopped","toolUses":0}
        ]}}
        """
        let envelope = try decode(ServerEnvelope.self, json)
        guard case .subagentList(let agentId, let items) = envelope.message else {
            Issue.record("esperava subagentList")
            return
        }
        #expect(agentId == "w17:p1")
        #expect(items.map(\.agentId) == ["a1", "a5"])
        #expect(items.last?.parentAgentId == "a1")
    }

    @Test func emptySubagentListRoundTrips() throws {
        let envelope = ServerEnvelope(id: "c-2", message: .subagentList(agentId: "w1:p1", items: []))
        let decoded = try JSONDecoder().decode(ServerEnvelope.self, from: JSONEncoder().encode(envelope))
        #expect(decoded == envelope)
        #expect(try encodedJSON(envelope)["payload"] == .object(["agentId": .string("w1:p1"), "items": .array([])]))
    }
}

@Suite struct SubagentChatItemTests {
    @Test func subagentFieldsAreFlattenedIntoTheChatItem() throws {
        let call = SubagentCall(
            toolUseId: "t1",
            agentId: "a1",
            agentType: "Explore",
            description: "Mapear",
            status: .running,
            activity: ToolActivity(toolName: "Read", summary: "a.swift", status: .running),
            toolUses: 2,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let json = try encodedJSON(ChatItem(id: "i", at: Date(timeIntervalSince1970: 0), kind: .subagent(call)))
        #expect(json == .object([
            "id": .string("i"), "at": .string("1970-01-01T00:00:00.000Z"), "type": .string("subagent"),
            "toolUseId": .string("t1"), "agentId": .string("a1"), "agentType": .string("Explore"),
            "description": .string("Mapear"), "status": .string("running"),
            "activity": .object(["toolName": .string("Read"), "summary": .string("a.swift"), "status": .string("running")]),
            "toolUses": .number(2), "startedAt": .string("1970-01-01T00:00:01.000Z"),
        ]))
    }

    @Test func subagentBeforeLaunchOmitsTheOptionalFields() throws {
        let item = try decode(
            ChatItem.self,
            #"{"id":"i","at":"2026-09-26T13:52:10.000Z","type":"subagent","toolUseId":"t1","agentType":"general-purpose","description":"d","status":"running","toolUses":0}"#
        )
        guard case .subagent(let call) = item.kind else {
            Issue.record("esperava subagent")
            return
        }
        #expect(call.agentId == nil)
        #expect(call.activity == nil)
        #expect(call.startedAt == nil)
        #expect(call.durationMs == nil)
        #expect(call.failureReason == nil)
        let json = try encodedJSON(item)
        for key in ["agentId", "activity", "startedAt", "durationMs", "failureReason"] {
            #expect(json[key] == nil, "\(key)")
        }
    }

    @Test func workflowPhasesAndAgentsAreNestedLists() throws {
        let workflow = WorkflowCall(
            toolUseId: "t1",
            name: "auditoria",
            status: .running,
            phases: [
                WorkflowPhase(title: "Mapear", status: .running, agents: [WorkflowAgent(agentId: "a1", label: "L", status: .running)]),
                WorkflowPhase(title: "Revisar", status: .pending),
            ],
            agentCount: 1
        )
        let json = try encodedJSON(ChatItem(id: "i", at: Date(timeIntervalSince1970: 0), kind: .workflow(workflow)))
        #expect(json == .object([
            "id": .string("i"), "at": .string("1970-01-01T00:00:00.000Z"), "type": .string("workflow"),
            "toolUseId": .string("t1"), "name": .string("auditoria"), "status": .string("running"),
            "phases": .array([
                .object([
                    "title": .string("Mapear"), "status": .string("running"),
                    "agents": .array([.object(["agentId": .string("a1"), "label": .string("L"), "status": .string("running")])]),
                ]),
                .object(["title": .string("Revisar"), "status": .string("pending"), "agents": .array([])]),
            ]),
            "agentCount": .number(1), "toolUses": .number(0),
        ]))
    }

    @Test func taskCarriesItsText() throws {
        let item = ChatItem(id: "i", at: Date(timeIntervalSince1970: 0), kind: .task(text: "Rode os testes"))
        #expect(try encodedJSON(item)["text"] == .string("Rode os testes"))
        #expect(try JSONDecoder().decode(ChatItem.self, from: JSONEncoder().encode(item)) == item)
    }

    @Test func unknownStatusesDropTheItemFromTolerantLists() throws {
        let items = """
        [{"id":"a","at":"2026-09-26T13:52:10.000Z","type":"subagent","toolUseId":"t1","agentType":"Explore","description":"d","status":"paused","toolUses":0},
         {"id":"b","at":"2026-09-26T13:52:10.000Z","type":"workflow","toolUseId":"t2","name":"w","status":"paused","phases":[],"agentCount":0,"toolUses":0},
         {"id":"c","at":"2026-09-26T13:52:10.000Z","type":"workflow","toolUseId":"t3","name":"w","status":"running","phases":[{"title":"F","status":"skipped","agents":[]}],"agentCount":0,"toolUses":0},
         {"id":"d","at":"2026-09-26T13:52:10.000Z","type":"workflow","toolUseId":"t4","name":"w","status":"running","phases":[{"title":"F","status":"running","agents":[{"agentId":"a1","label":"L","status":"paused"}]}],"agentCount":1,"toolUses":0},
         {"id":"e","at":"2026-09-26T13:52:10.000Z","type":"subagent","toolUseId":"t5","agentType":"Explore","description":"d","status":"running","activity":{"toolName":"Bash","summary":"ls","status":"paused"},"toolUses":1},
         {"id":"f","at":"2026-09-26T13:52:10.000Z","type":"task"},
         {"id":"g","at":"2026-09-26T13:52:10.000Z","type":"subagent","toolUseId":"t6","agentType":"Explore","description":"d","status":"completed","toolUses":3,"durationMs":1200},
         {"id":"h","at":"2026-09-26T13:52:10.000Z","type":"workflow","toolUseId":"t7","name":"w","status":"stopped","phases":[],"agentCount":0,"toolUses":0},
         {"id":"i","at":"2026-09-26T13:52:10.000Z","type":"task","text":"t"}]
        """
        #expect(try chatUpdateItems(items).map(\.id) == ["g", "h", "i"])
    }

    @Test func unknownItemTypesStillDecodeAsUnsupported() throws {
        let items = #"[{"id":"a","at":"2026-09-26T13:52:10.000Z","type":"teamRun","members":3},{"id":"b","at":"2026-09-26T13:52:10.000Z","type":"task","text":"t"}]"#
        #expect(try chatUpdateItems(items).map(\.kind) == [.unsupported(type: "teamRun"), .task(text: "t")])
    }
}

@Suite struct SubagentCompatibilityTests {
    @Test func agentSummaryWithoutRunningSubagentsDecodesAsNil() throws {
        let agent = try decode(
            AgentSummary.self,
            #"{"id":"w1:p1","kind":"claude","status":"idle","title":"t","workspaceLabel":"w","sessionId":"s1","pendingCount":0}"#
        )
        #expect(agent.runningSubagents == nil)
        #expect(try encodedJSON(agent)["runningSubagents"] == nil)
    }

    @Test func subagentsTreeFixtureCarriesTheRunningCounts() throws {
        let envelope = try JSONDecoder().decode(ServerEnvelope.self, from: ProtocolFixtures.data("server.tree.subagents.json"))
        guard case .tree(let workspaces) = envelope.message else {
            Issue.record("esperava tree")
            return
        }
        let counts = workspaces.flatMap { $0.tabs.flatMap(\.agents) }.map(\.runningSubagents)
        #expect(counts == [1, 2, 0, nil])
    }

    @Test func chatMetaWithoutSubagentDecodesAsNilAndOmitsIt() throws {
        let meta = try decode(ChatMeta.self, #"{"title":"t","workspaceLabel":"w","status":"idle","permissionMode":"auto"}"#)
        #expect(meta.subagent == nil)
        #expect(meta.permissionMode == "auto")
        #expect(try encodedJSON(meta) == .object([
            "title": .string("t"), "workspaceLabel": .string("w"), "status": .string("idle"), "permissionMode": .string("auto"),
        ]))
    }

    @Test func invalidChatMetaSubagentDecodesAsNilWithoutBreakingTheMeta() throws {
        let invalid = [
            #"{"parentTitle":"p","agentType":"Explore","status":"paused","toolUses":1}"#,
            #"{"agentType":"Explore","status":"running","toolUses":1}"#,
            #"{"parentTitle":"p","agentType":"Explore","status":"running","toolUses":1,"startedAt":"ontem"}"#,
            #""texto""#,
        ]
        for subagent in invalid {
            let meta = try decode(
                ChatMeta.self,
                #"{"title":"t","workspaceLabel":"w","status":"unknown","subagent":"# + subagent + "}"
            )
            #expect(meta.subagent == nil, "\(subagent)")
            #expect(meta.title == "t")
        }
    }

    @Test func chatMetaSubagentRoundTrips() throws {
        let info = SubagentChatInfo(
            parentTitle: "Paginação",
            agentType: "Plan",
            status: .failed,
            startedAt: Date(timeIntervalSince1970: 60),
            durationMs: 48000,
            toolUses: 3,
            failureReason: "API Error: 500"
        )
        let meta = ChatMeta(title: "t", workspaceLabel: "w", status: .unknown, subagent: info)
        #expect(try JSONDecoder().decode(ChatMeta.self, from: JSONEncoder().encode(meta)) == meta)
        #expect(try encodedJSON(meta)["subagent"]?["startedAt"] == .string("1970-01-01T00:01:00.000Z"))
    }
}
