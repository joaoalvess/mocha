import Foundation
import Testing
@testable import MochaProtocol

enum ProtocolFixtures {
    static let names: [String] = ((try? FileManager.default
        .contentsOfDirectory(atPath: Fixtures.url("protocol").path(percentEncoded: false))) ?? [])
        .filter { $0.hasSuffix(".json") }
        .sorted()

    static func data(_ name: String) throws -> Data {
        try Fixtures.data("protocol/\(name)")
    }

    static func nameComponents(_ name: String) -> [String] {
        name.dropLast(".json".count).split(separator: ".").map(String.init)
    }
}

@discardableResult
func assertRoundTrip<Value: Codable & Equatable>(_ type: Value.Type, from data: Data) throws -> Value {
    let decoded = try JSONDecoder().decode(Value.self, from: data)
    let encoded = try JSONEncoder().encode(decoded)
    let redecoded = try JSONDecoder().decode(Value.self, from: encoded)
    #expect(redecoded == decoded)
    #expect(try JSONValue(data: encoded) == JSONValue(data: data))
    return decoded
}

@Suite struct FixtureRoundTripTests {
    @Test func fixturesDirectoryIsNotEmpty() {
        #expect(ProtocolFixtures.names.count >= 50)
    }

    @Test(arguments: ProtocolFixtures.names)
    func fixtureRoundTripsAndEncodesToTheSameJSON(_ name: String) throws {
        let data = try ProtocolFixtures.data(name)
        let components = ProtocolFixtures.nameComponents(name)
        let prefix = components[0]
        let type = components[1]

        switch prefix {
        case "client":
            let envelope = try assertRoundTrip(ClientEnvelope.self, from: data)
            #expect(envelope.message.type == type)
            #expect(envelope.message != .unknown(type: type))
            #expect(envelope.version == 1)
        case "server":
            let envelope = try assertRoundTrip(ServerEnvelope.self, from: data)
            #expect(envelope.message.type == type)
            #expect(envelope.message != .unknown(type: type))
            #expect(envelope.version == 1)
        case "chatItem":
            let item = try assertRoundTrip(ChatItem.self, from: data)
            if type == "unsupported" {
                guard case .unsupported = item.kind else {
                    Issue.record("\(name) deveria decodificar como .unsupported")
                    return
                }
            } else {
                #expect(item.kind.type == type)
                #expect(item.kind != .unsupported(type: type))
            }
        case "pendingRequest":
            let request = try assertRoundTrip(PendingRequest.self, from: data)
            #expect(request.kind.type == type)
        case "pendingResponse":
            let response = try assertRoundTrip(PendingResponse.self, from: data)
            #expect(response.type == type)
        default:
            Issue.record("Fixture sem decodificador conhecido: \(name)")
        }
    }

    @Test func everyMessageAndDomainCaseHasAFixture() {
        let clientTypes = [
            "hello", "openChat", "closeChat", "sendPrompt", "interrupt", "setForeground", "unpair", "ping",
            "archive", "slash", "setPreferences", "respond", "newAgentTab", "registerLiveActivity",
        ]
        let serverTypes = [
            "helloOk", "tree", "archived", "usage", "herdrStatus", "treeChanged", "agentStatus", "chatPage",
            "chatAppend", "chatUpdate", "chatMeta", "pending", "ack", "pong", "error",
        ]
        let chatItemTypes = [
            "userPrompt", "slashCommand", "assistantText", "thinking", "toolCall", "turnFooter", "recap", "notice",
            "unsupported",
        ]
        let expected = clientTypes.map { "client.\($0).json" }
            + serverTypes.map { "server.\($0).json" }
            + chatItemTypes.map { "chatItem.\($0).json" }
            + ["permission", "question"].map { "pendingRequest.\($0).json" }
            + ["allow", "deny", "answers"].map { "pendingResponse.\($0).json" }
            + ["client.openChat", "client.closeChat", "server.chatPage", "server.chatAppend"].map { "\($0).session.json" }
            + ["server.usage.noPlan.json", "server.tree.home.json"]

        for name in expected {
            #expect(ProtocolFixtures.names.contains(name), "Falta a fixture \(name)")
        }
    }

    @Test(arguments: CanonicalExamples.all)
    func canonicalExamplesMatchTheirFixtures(_ example: CanonicalExample) throws {
        let fixture = try JSONValue(data: ProtocolFixtures.data(example.fixture))
        let canonical = try JSONValue(data: Data(example.json.utf8))
        #expect(fixture == canonical)
    }
}

struct CanonicalExample: Sendable, CustomTestStringConvertible {
    let fixture: String
    let json: String

    var testDescription: String { fixture }
}

enum CanonicalExamples {
    static let chatPageItems = [
        #"{"id":"8f1c…","at":"2026-09-25T15:44:34.551Z","type":"userPrompt","text":"roda os testes","imageCount":0}"#,
        #"{"id":"9a2d…","at":"2026-09-25T15:44:40.120Z","type":"assistantText","markdown":"Rodando `scripts/test.sh`…"}"#,
        #"{"id":"b7e0…","at":"2026-09-25T15:44:41.000Z","type":"toolCall","toolUseId":"toolu_01H3…","name":"Bash","summary":"scripts/test.sh","inputJSON":"{\"command\":\"scripts/test.sh\"}","status":"succeeded","resultPreview":"All tests passed"}"#,
        #"{"id":"c1f4…","at":"2026-09-25T15:45:10.000Z","type":"turnFooter","durationMs":45000}"#,
        #"{"id":"d2a9…","at":"2026-09-25T15:45:11.000Z","type":"slashCommand","name":"/clear","args":""}"#,
    ]

    static let all: [CanonicalExample] = [
        CanonicalExample(fixture: "chatItem.userPrompt.json", json: chatPageItems[0]),
        CanonicalExample(fixture: "chatItem.assistantText.json", json: chatPageItems[1]),
        CanonicalExample(fixture: "chatItem.toolCall.json", json: chatPageItems[2]),
        CanonicalExample(fixture: "chatItem.turnFooter.json", json: chatPageItems[3]),
        CanonicalExample(fixture: "chatItem.slashCommand.json", json: chatPageItems[4]),
        CanonicalExample(
            fixture: "pendingRequest.permission.json",
            json: #"{"id":"5e3b…","agentId":"w17:p1","createdAt":"2026-09-25T15:50:00.000Z","type":"permission","toolName":"Bash","summary":"rm -rf build","inputJSON":"{\"command\":\"rm -rf build\"}"}"#
        ),
        CanonicalExample(
            fixture: "pendingRequest.question.json",
            json: #"{"id":"6f4c…","agentId":"w17:p1","createdAt":"2026-09-25T15:51:00.000Z","type":"question","questions":[{"header":"Formato","question":"Qual formato?","multiSelect":false,"options":[{"label":"JSON","description":"…"},{"label":"YAML"}]}]}"#
        ),
        CanonicalExample(fixture: "pendingResponse.allow.json", json: #"{"type":"allow"}"#),
        CanonicalExample(fixture: "pendingResponse.deny.json", json: #"{"type":"deny","reason":"não apaga isso"}"#),
        CanonicalExample(
            fixture: "pendingResponse.answers.json",
            json: #"{"type":"answers","answers":{"Qual formato?":["JSON"]}}"#
        ),
        CanonicalExample(
            fixture: "client.openChat.json",
            json: #"{"v":1,"id":"c-7","type":"openChat","payload":{"agentId":"w17:p1","limit":60}}"#
        ),
        CanonicalExample(
            fixture: "server.chatPage.json",
            json: #"{"v":1,"id":"c-7","type":"chatPage","payload":{"agentId":"w17:p1","meta":{"title":"herdr-sidebar abre arquivos em nova tab","workspaceLabel":"Core","model":"claude-opus-5-5","branch":"development","status":"idle"},"items":["#
                + chatPageItems.joined(separator: ",")
                + #"],"before":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64:120394","hasMore":true}}"#
        ),
        CanonicalExample(
            fixture: "server.agentStatus.json",
            json: #"{"v":1,"type":"agentStatus","payload":{"agentId":"w17:p1","status":"working"}}"#
        ),
        CanonicalExample(fixture: "server.ack.json", json: #"{"v":1,"id":"c-9","type":"ack","payload":{}}"#),
        CanonicalExample(
            fixture: "client.openChat.session.json",
            json: #"{"v":1,"id":"c-11","type":"openChat","payload":{"sessionId":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64","limit":60}}"#
        ),
        CanonicalExample(
            fixture: "server.usage.json",
            json: #"{"v":1,"type":"usage","payload":{"plan":"Max 20x","account":"d•••@e•••.com","windows":[{"kind":"fiveHour","usedPercent":12,"resetsAt":"2026-09-26T07:00:00.000Z"},{"kind":"weekly","usedPercent":71,"resetsAt":"2026-09-28T14:00:00.000Z"}],"fetchedAt":"2026-09-26T03:21:03.000Z"}}"#
        ),
        CanonicalExample(
            fixture: "server.error.json",
            json: #"{"v":1,"id":"c-9","type":"error","payload":{"code":"agentBlocked","message":"O agente está esperando uma resposta no terminal."}}"#
        ),
    ]
}
