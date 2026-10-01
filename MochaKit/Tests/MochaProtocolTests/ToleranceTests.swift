import Foundation
import Testing
@testable import MochaProtocol

private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(json.utf8))
}

private func encodedJSON<Value: Encodable>(_ value: Value) throws -> JSONValue {
    try JSONValue(data: JSONEncoder().encode(value))
}

@Suite struct UnknownTypeTests {
    @Test func unknownClientTypeDecodesAsUnknownWithoutThrowing() throws {
        let envelope = try decode(
            ClientEnvelope.self,
            #"{"v":1,"id":"c-99","type":"teleport","payload":{"destination":"lua"}}"#
        )
        #expect(envelope.id == "c-99")
        #expect(envelope.message == .unknown(type: "teleport"))
    }

    @Test func unknownServerTypeDecodesAsUnknownWithoutThrowing() throws {
        let event = try decode(ServerEnvelope.self, #"{"v":1,"type":"weather","payload":{"sunny":true}}"#)
        #expect(event.id == nil)
        #expect(event.message == .unknown(type: "weather"))

        let response = try decode(ServerEnvelope.self, #"{"v":1,"id":"c-3","type":"teleported"}"#)
        #expect(response.id == "c-3")
        #expect(response.message == .unknown(type: "teleported"))
    }

    @Test func unknownChatItemTypeDecodesAsUnsupported() throws {
        let item = try decode(
            ChatItem.self,
            #"{"id":"x1","at":"2026-09-25T15:44:34.551Z","type":"hologram","depth":3,"text":"oi"}"#
        )
        #expect(item.id == "x1")
        #expect(item.kind == .unsupported(type: "hologram"))
    }

    @Test func unknownChatItemInsideAListIsKeptAsUnsupported() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"type":"chatAppend","payload":{"agentId":"w1:p1","items":[{"id":"a","at":"2026-09-25T15:44:34.551Z","type":"hologram"},{"id":"b","at":"2026-09-25T15:44:35.000Z","type":"notice","text":"ok"}]}}"#
        )
        guard case .chatAppend(_, let items) = envelope.message else {
            Issue.record("esperava chatAppend")
            return
        }
        #expect(items.map(\.kind) == [.unsupported(type: "hologram"), .notice(text: "ok")])
    }

    @Test func unknownPendingKindThrows() {
        #expect(throws: DecodingError.self) {
            try decode(
                PendingRequest.self,
                #"{"id":"r1","agentId":"w1:p1","createdAt":"2026-09-25T15:50:00.000Z","type":"vote"}"#
            )
        }
    }

    @Test func unknownPendingResponseThrows() {
        #expect(throws: DecodingError.self) {
            try decode(PendingResponse.self, #"{"type":"maybe"}"#)
        }
    }

    @Test func unknownAgentStatusDecodesAsUnknown() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"type":"agentStatus","payload":{"agentId":"w1:p1","status":"sleeping"}}"#
        )
        #expect(envelope.message == .agentStatus(agentId: "w1:p1", status: .unknown))
    }

    @Test func unknownErrorCodeIsPreserved() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"id":"c-1","type":"error","payload":{"code":"rateLimited","message":"Calma."}}"#
        )
        #expect(envelope.message == .error(code: ProtocolErrorCode(rawValue: "rateLimited"), message: "Calma."))
        #expect(try encodedJSON(envelope)["payload"]?["code"] == .string("rateLimited"))
    }
}

@Suite struct LossyListTests {
    @Test func invalidPendingRequestIsDroppedAndTheOthersAreKept() throws {
        let json = """
        {"v":1,"type":"pending","payload":{"requests":[
          {"id":"r1","agentId":"w1:p1","createdAt":"2026-09-25T15:50:00.000Z","type":"permission","toolName":"Bash","summary":"ls","inputJSON":"{}"},
          {"id":"r2","agentId":"w1:p1","createdAt":"2026-09-25T15:50:01.000Z","type":"vote"},
          {"id":"r3","agentId":"w1:p1","createdAt":"2026-09-25T15:50:02.000Z","type":"permission","toolName":"Bash"},
          {"id":"r4","agentId":"w1:p1","createdAt":"ontem","type":"permission","toolName":"Bash","summary":"ls","inputJSON":"{}"},
          42,
          {"id":"r5","agentId":"w2:p1","createdAt":"2026-09-25T15:51:00.000Z","type":"question","questions":[{"header":"H","question":"Q?","multiSelect":true,"options":[{"label":"A"}]}]}
        ]}}
        """
        let envelope = try decode(ServerEnvelope.self, json)
        guard case .pending(let requests) = envelope.message else {
            Issue.record("esperava pending")
            return
        }
        #expect(requests.map(\.id) == ["r1", "r5"])
    }

    @Test func invalidChatItemsAreDroppedFromChatAppendAndChatUpdate() throws {
        let items = """
        [{"id":"a","at":"2026-09-25T15:44:34.551Z","type":"userPrompt","text":"oi","imageCount":0},
         {"id":"b","at":"2026-09-25T15:44:35.000Z","type":"userPrompt"},
         {"id":"c","type":"notice","text":"sem data"},
         "texto solto",
         {"id":"d","at":"2026-09-25T15:44:36.000Z","type":"toolCall","toolUseId":"t1","name":"Bash","summary":"ls","inputJSON":"{}","status":"exploded"},
         {"id":"e","at":"2026-09-25T15:44:37.000Z","type":"turnFooter","durationMs":1200}]
        """
        for type in ["chatAppend", "chatUpdate"] {
            let envelope = try decode(
                ServerEnvelope.self,
                #"{"v":1,"type":""# + type + #"","payload":{"agentId":"w1:p1","items":"# + items + "}}"
            )
            switch envelope.message {
            case .chatAppend(_, let decoded), .chatUpdate(_, let decoded):
                #expect(decoded.map(\.id) == ["a", "e"])
            default:
                Issue.record("esperava \(type)")
            }
        }
    }

    @Test func invalidChatItemIsDroppedFromChatPage() throws {
        let envelope = try decode(
            ServerEnvelope.self,
            #"{"v":1,"id":"c-2","type":"chatPage","payload":{"agentId":"w1:p1","meta":{"title":"t","workspaceLabel":"w","status":"idle"},"items":[{"id":"a","at":"2026-09-25T15:44:34.551Z","type":"recap"},{"id":"b","at":"2026-09-25T15:44:35.000Z","type":"recap","text":"ok"}],"hasMore":false}}"#
        )
        guard case .chatPage(let page) = envelope.message else {
            Issue.record("esperava chatPage")
            return
        }
        #expect(page.items.map(\.id) == ["b"])
        #expect(page.before == nil)
    }
}

@Suite struct EnvelopeTests {
    @Test func missingPayloadIsEquivalentToEmptyObject() throws {
        #expect(try decode(ClientEnvelope.self, #"{"v":1,"id":"c-1","type":"ping"}"#).message == .ping)
        #expect(try decode(ClientEnvelope.self, #"{"v":1,"id":"c-2","type":"unpair","payload":null}"#).message == .unpair)
        #expect(try decode(ServerEnvelope.self, #"{"v":1,"id":"c-3","type":"ack"}"#).message == .ack())
        #expect(try decode(ServerEnvelope.self, #"{"v":1,"id":"c-3","type":"ack","payload":{}}"#).message == .ack())
        #expect(try decode(ServerEnvelope.self, #"{"v":1,"id":"c-4","type":"pong"}"#).message == .pong)

        for type in ["sendPrompt", "hello", "setPreferences", "registerLiveActivity"] {
            #expect(throws: DecodingError.self) {
                try decode(ClientEnvelope.self, #"{"v":1,"id":"c-5","type":""# + type + #""}"#)
            }
            #expect(throws: DecodingError.self) {
                try decode(ClientEnvelope.self, #"{"v":1,"id":"c-5","type":""# + type + #"","payload":{}}"#)
            }
        }
    }

    @Test func emptyPayloadIsEncodedAsEmptyObject() throws {
        let json = try encodedJSON(ClientEnvelope(id: "c-1", message: .ping))
        #expect(json == .object(["v": .number(2), "id": .string("c-1"), "type": .string("ping"), "payload": .object([:])]))
    }

    @Test func clientMessagesRequireAnId() {
        #expect(throws: DecodingError.self) {
            try decode(ClientEnvelope.self, #"{"v":1,"type":"ping","payload":{}}"#)
        }
    }

    @Test func serverEventsAreEncodedWithoutId() throws {
        let event = ServerEnvelope(message: .agentStatus(agentId: "w1:p1", status: .working))
        #expect(try encodedJSON(event)["id"] == nil)
        let response = ServerEnvelope(id: "c-9", message: .ack())
        #expect(try encodedJSON(response)["id"] == .string("c-9"))
    }

    @Test func headerReadsWhatItCanFromAnInvalidEnvelope() throws {
        let header = try decode(EnvelopeHeader.self, #"{"v":2,"id":"c-8","type":"sendPrompt","payload":{"agentId":7}}"#)
        #expect(header == EnvelopeHeader(version: 2, id: "c-8", type: "sendPrompt"))

        let partial = try decode(EnvelopeHeader.self, #"{"v":"um","type":"ping"}"#)
        #expect(partial == EnvelopeHeader(version: nil, id: nil, type: "ping"))
    }

    @Test func versionIsDecodedWithoutValidation() throws {
        let envelope = try decode(ClientEnvelope.self, #"{"v":2,"id":"c-1","type":"ping"}"#)
        #expect(envelope.version == 2)
    }
}

@Suite struct OmissionTests {
    @Test func nilOptionalsAreOmitted() throws {
        let item = ChatItem(id: "t", at: Date(timeIntervalSince1970: 0), kind: .thinking(text: nil))
        #expect(try encodedJSON(item) == .object([
            "id": .string("t"), "at": .string("1970-01-01T00:00:00.000Z"), "type": .string("thinking"),
        ]))

        let agent = AgentSummary(id: "w1:p2", kind: "codex", status: .idle, title: "codex", workspaceLabel: "w")
        let agentJSON = try encodedJSON(agent)
        for key in ["model", "branch", "sessionId", "lastActivityAt"] {
            #expect(agentJSON[key] == nil)
        }

        let open = ClientEnvelope(id: "c-1", message: .openChat(target: .agent("w1:p1")))
        #expect(try encodedJSON(open)["payload"] == .object(["agentId": .string("w1:p1")]))
    }

    @Test func toolCallFieldsAreFlattenedIntoTheChatItem() throws {
        let call = ToolCall(toolUseId: "t1", name: "Read", summary: "a.swift", inputJSON: "{}", status: .running)
        let json = try encodedJSON(ChatItem(id: "i", at: Date(timeIntervalSince1970: 0), kind: .toolCall(call)))
        #expect(json == .object([
            "id": .string("i"), "at": .string("1970-01-01T00:00:00.000Z"), "type": .string("toolCall"),
            "toolUseId": .string("t1"), "name": .string("Read"), "summary": .string("a.swift"),
            "inputJSON": .string("{}"), "status": .string("running"),
        ]))
    }

    @Test func missingImagePathsDecodeAsEmptyAndEmptyImagePathsAreOmitted() throws {
        let item = try decode(
            ChatItem.self,
            #"{"id":"a","at":"2026-09-25T15:44:34.551Z","type":"userPrompt","text":"oi","imageCount":1}"#
        )
        #expect(item.imagePaths.isEmpty)
        #expect(try encodedJSON(item)["imagePaths"] == nil)
    }

    @Test func imagePathsAreFlattenedNextToTheItemFields() throws {
        let call = ToolCall(toolUseId: "t1", name: "Read", summary: "a.png", inputJSON: "{}", status: .succeeded)
        let item = ChatItem(id: "i", at: Date(timeIntervalSince1970: 0), kind: .toolCall(call), imagePaths: ["/tmp/a.png"])
        let json = try encodedJSON(item)
        #expect(json["imagePaths"] == .array([.string("/tmp/a.png")]))
        #expect(json["toolUseId"] == .string("t1"))
        #expect(try decode(ChatItem.self, String(decoding: JSONEncoder().encode(item), as: UTF8.self)) == item)
    }
}
