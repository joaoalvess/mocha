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

private extension ClientMessage {
    var chatTarget: ChatTarget? {
        switch self {
        case .openChat(let target, _, _), .closeChat(let target): target
        default: nil
        }
    }
}

private extension ServerMessage {
    var chatTarget: ChatTarget? {
        switch self {
        case .chatPage(let page): page.target
        case .chatAppend(let target, _), .chatUpdate(let target, _), .chatMeta(let target, _): target
        default: nil
        }
    }
}

struct TargetedMessage: Sendable, CustomTestStringConvertible {
    let isClient: Bool
    let type: String
    let otherFields: String

    var testDescription: String { (isClient ? "client." : "server.") + type }

    static let meta = #""meta":{"title":"t","workspaceLabel":"w","status":"idle"}"#

    static let all: [TargetedMessage] = [
        TargetedMessage(isClient: true, type: "openChat", otherFields: #""limit":60"#),
        TargetedMessage(isClient: true, type: "closeChat", otherFields: ""),
        TargetedMessage(isClient: false, type: "chatPage", otherFields: meta + #","items":[],"hasMore":false"#),
        TargetedMessage(isClient: false, type: "chatAppend", otherFields: #""items":[]"#),
        TargetedMessage(isClient: false, type: "chatUpdate", otherFields: #""items":[]"#),
        TargetedMessage(isClient: false, type: "chatMeta", otherFields: meta),
    ]

    func json(targetFields: String) -> String {
        let fields = [targetFields, otherFields].filter { !$0.isEmpty }.joined(separator: ",")
        let id = isClient ? #""id":"c-1","# : ""
        return #"{"v":1,"# + id + #""type":""# + type + #"","payload":{"# + fields + "}}"
    }

    func decodedTarget(targetFields: String) throws -> ChatTarget? {
        let json = json(targetFields: targetFields)
        if isClient {
            return try decode(ClientEnvelope.self, json).message.chatTarget
        }
        return try decode(ServerEnvelope.self, json).message.chatTarget
    }
}

@Suite struct ChatTargetCodingTests {
    @Test(arguments: TargetedMessage.all)
    func exactlyOneTargetFieldDecodes(_ message: TargetedMessage) throws {
        #expect(try message.decodedTarget(targetFields: #""agentId":"w1:p1""#) == .agent("w1:p1"))
        #expect(try message.decodedTarget(targetFields: #""sessionId":""# + sessionId + #"""#) == .session(sessionId))
    }

    @Test(arguments: TargetedMessage.all)
    func bothTargetFieldsThrow(_ message: TargetedMessage) {
        #expect(throws: DecodingError.self) {
            try message.decodedTarget(targetFields: #""agentId":"w1:p1","sessionId":""# + sessionId + #"""#)
        }
    }

    @Test(arguments: TargetedMessage.all)
    func missingTargetFieldsThrow(_ message: TargetedMessage) {
        #expect(throws: DecodingError.self) {
            try message.decodedTarget(targetFields: "")
        }
    }

    @Test func targetIsFlattenedIntoThePayload() throws {
        let openSession = ClientEnvelope(id: "c-1", message: .openChat(target: .session(sessionId), limit: 60))
        #expect(try encodedJSON(openSession)["payload"] == .object([
            "sessionId": .string(sessionId), "limit": .number(60),
        ]))

        let closeAgent = ClientEnvelope(id: "c-2", message: .closeChat(target: .agent("w1:p1")))
        #expect(try encodedJSON(closeAgent)["payload"] == .object(["agentId": .string("w1:p1")]))

        let meta = ChatMeta(title: "t", workspaceLabel: "w", status: .unknown)
        let metaEvent = ServerEnvelope(message: .chatMeta(target: .session(sessionId), meta: meta))
        let payload = try encodedJSON(metaEvent)["payload"]
        #expect(payload?["sessionId"] == .string(sessionId))
        #expect(payload?["agentId"] == nil)

        let page = ChatPage(target: .session(sessionId), meta: meta, items: [], before: nil, hasMore: false)
        let pageJSON = try encodedJSON(page)
        #expect(pageJSON["sessionId"] == .string(sessionId))
        #expect(pageJSON["agentId"] == nil)
    }

    @Test(arguments: ProtocolFixtures.names.filter { $0.hasSuffix(".session.json") })
    func sessionFixturesUseTheSessionTarget(_ name: String) throws {
        let data = try ProtocolFixtures.data(name)
        let target: ChatTarget? = if name.hasPrefix("client.") {
            try JSONDecoder().decode(ClientEnvelope.self, from: data).message.chatTarget
        } else {
            try JSONDecoder().decode(ServerEnvelope.self, from: data).message.chatTarget
        }
        guard case .session = target else {
            Issue.record("\(name) deveria usar ChatTarget.session, veio \(String(describing: target))")
            return
        }
    }

    @Test func agentOnlyMessagesRejectASessionId() {
        let payloads = [
            ("sendPrompt", #""sessionId":""# + sessionId + #"","text":"oi""#),
            ("interrupt", #""sessionId":""# + sessionId + #"""#),
            ("slash", #""sessionId":""# + sessionId + #"","command":"/compact""#),
        ]
        for (type, fields) in payloads {
            #expect(throws: DecodingError.self, "\(type)") {
                try decode(ClientEnvelope.self, #"{"v":1,"id":"c-1","type":""# + type + #"","payload":{"# + fields + "}}")
            }
        }
    }

    @Test func archiveRequiresASessionId() throws {
        let envelope = try decode(
            ClientEnvelope.self,
            #"{"v":1,"id":"c-1","type":"archive","payload":{"sessionId":""# + sessionId + #""}}"#
        )
        #expect(envelope.message == .archive(sessionId: sessionId))
        #expect(throws: DecodingError.self) {
            try decode(ClientEnvelope.self, #"{"v":1,"id":"c-1","type":"archive","payload":{"agentId":"w1:p1"}}"#)
        }
    }
}

@Suite struct ScopeBUnknownValueTests {
    @Test func unknownArchiveReasonDecodesAsUnknown() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"type":"archived","payload":{"sessions":[{"id":"s1","title":"t","workspaceLabel":"w","reason":"compacted","endedAt":"2026-09-26T02:58:41.310Z"}]}}"#
        )
        guard case .archived(let sessions) = envelope.message else {
            Issue.record("esperava archived")
            return
        }
        #expect(sessions.map(\.reason) == [.unknown])
    }

    @Test func unknownUsageWindowKindDecodesAsUnknown() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"type":"usage","payload":{"windows":[{"kind":"monthly","usedPercent":5},{"kind":"weekly","usedPercent":71}],"fetchedAt":"2026-09-26T03:21:03.000Z"}}"#
        )
        guard case .usage(let snapshot) = envelope.message else {
            Issue.record("esperava usage")
            return
        }
        #expect(snapshot.windows.map(\.kind) == [.unknown, .weekly])
    }

    @Test func sessionNotFoundIsAKnownErrorCode() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"id":"c-1","type":"error","payload":{"code":"sessionNotFound","message":"Sessão não encontrada."}}"#
        )
        #expect(envelope.message == .error(code: .sessionNotFound, message: "Sessão não encontrada."))
    }
}

@Suite struct ScopeBLossyListTests {
    @Test func invalidArchivedSessionIsDroppedAndTheOthersAreKept() throws {
        let json = """
        {"v":1,"type":"archived","payload":{"sessions":[
          {"id":"s1","title":"t","workspaceLabel":"w","reason":"cleared","endedAt":"2026-09-26T02:58:41.310Z"},
          {"id":"s2","title":"t","workspaceLabel":"w","reason":"ended"},
          {"id":"s3","title":"t","workspaceLabel":"w","reason":"ended","endedAt":"ontem"},
          {"id":"s4","title":"t","workspaceLabel":"w","reason":"ended","endedAt":"2026-09-26T02:00:00.000Z","preview":{"author":"robot","text":"oi"}},
          "sessão solta",
          {"id":"s5","workspaceLabel":"w","reason":"ended","endedAt":"2026-09-26T01:00:00.000Z"},
          {"id":"s6","title":"t","workspaceLabel":"w","reason":"ended","endedAt":"2026-09-25T22:14:09.000Z","preview":{"author":"user","text":"oi"}}
        ]}}
        """
        let envelope = try decode(ServerEnvelope.self, json)
        guard case .archived(let sessions) = envelope.message else {
            Issue.record("esperava archived")
            return
        }
        #expect(sessions.map(\.id) == ["s1", "s6"])
    }

    @Test func invalidUsageWindowIsDroppedAndTheSnapshotIsKept() throws {
        let json = """
        {"v":1,"type":"usage","payload":{"plan":"Max 20x","windows":[
          {"kind":"fiveHour","usedPercent":12,"resetsAt":"2026-09-26T07:00:00.000Z"},
          {"kind":"weekly"},
          {"kind":"weekly","usedPercent":"71"},
          {"kind":"weekly","usedPercent":71,"resetsAt":"segunda"},
          42,
          {"kind":"weekly","usedPercent":71.5}
        ],"fetchedAt":"2026-09-26T03:21:03.000Z"}}
        """
        let envelope = try decode(ServerEnvelope.self, json)
        guard case .usage(let snapshot) = envelope.message else {
            Issue.record("esperava usage")
            return
        }
        #expect(snapshot.plan == "Max 20x")
        #expect(snapshot.account == nil)
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(snapshot.windows.map(\.usedPercent) == [12, 71.5])
        #expect(snapshot.windows.last?.resetsAt == nil)
    }
}

@Suite struct AgentSummaryCompatibilityTests {
    @Test func agentSummaryWithoutTheNewFieldsDecodesWithThemNil() throws {
        let agent = try decode(
            AgentSummary.self,
            #"{"id":"w1:p1","kind":"claude","status":"idle","title":"t","workspaceLabel":"w","sessionId":"s1","lastActivityAt":"2026-09-25T15:45:10.000Z","pendingCount":0}"#
        )
        #expect(agent.preview == nil)
        #expect(agent.activity == nil)
        #expect(agent.contextLeftPercent == nil)
        #expect(agent.sessionStartedAt == nil)
        #expect(agent.turnStartedAt == nil)
        #expect(agent.turnEndedAt == nil)
        #expect(agent.archivedAt == nil)
    }

    @Test func nilNewFieldsAreOmitted() throws {
        let agent = AgentSummary(id: "w1:p1", kind: "claude", status: .idle, title: "t", workspaceLabel: "w")
        let json = try encodedJSON(agent)
        for key in [
            "preview", "activity", "contextLeftPercent", "sessionStartedAt", "turnStartedAt", "turnEndedAt", "archivedAt",
        ] {
            #expect(json[key] == nil, "\(key)")
        }
    }

    @Test func homeTreeFixtureCoversEveryNewField() throws {
        let envelope = try JSONDecoder().decode(ServerEnvelope.self, from: ProtocolFixtures.data("server.tree.home.json"))
        guard case .tree(let workspaces) = envelope.message else {
            Issue.record("esperava tree")
            return
        }
        let agents = allAgents(in: workspaces)
        let complete = agents.filter { agent in
            agent.preview != nil && agent.activity != nil && agent.contextLeftPercent != nil
                && agent.sessionStartedAt != nil && agent.turnStartedAt != nil && agent.turnEndedAt != nil
                && agent.archivedAt != nil
        }
        #expect(!complete.isEmpty)
        #expect(agents.contains { $0.kind == "claude" && $0.sessionId != nil && $0.preview == nil })
    }

    private func allAgents(in workspaces: [WorkspaceNode]) -> [AgentSummary] {
        workspaces.flatMap { workspace in
            workspace.tabs.flatMap(\.agents) + allAgents(in: workspace.children)
        }
    }
}

@Test func invalidPreviewAndActivityDecodeAsNilWithoutBreakingTheAgent() throws {
    let json = #"{"id":"w17:p1","kind":"claude","status":"idle","title":"t","workspaceLabel":"Core","pendingCount":0,"preview":{"author":"robot","text":"x"},"activity":{"toolName":"Bash","summary":"ls","status":"paused"}}"#
    let agent = try JSONDecoder().decode(AgentSummary.self, from: Data(json.utf8))
    #expect(agent.preview == nil)
    #expect(agent.activity == nil)
}
