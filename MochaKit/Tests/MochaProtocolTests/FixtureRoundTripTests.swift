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
            #expect([1, ProtocolVersion.current].contains(envelope.version))
        case "server":
            let envelope = try assertRoundTrip(ServerEnvelope.self, from: data)
            #expect(envelope.message.type == type)
            #expect(envelope.message != .unknown(type: type))
            #expect([1, ProtocolVersion.current].contains(envelope.version))
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
        case "http":
            #expect(type == "uploadResponse")
            try assertRoundTrip(UploadResponse.self, from: data)
        default:
            Issue.record("Fixture sem decodificador conhecido: \(name)")
        }
    }

    @Test func everyMessageAndDomainCaseHasAFixture() {
        let clientTypes = [
            "hello", "openChat", "closeChat", "sendPrompt", "interrupt", "closeAgent", "setForeground", "unpair", "ping",
            "archive", "slash", "setPreferences", "respond", "newAgentTab", "registerLiveActivity", "listSubagents",
            "listWebServers", "setModel", "setEffort", "setMode",
        ]
        let serverTypes = [
            "helloOk", "tree", "archived", "usage", "herdrStatus", "treeChanged", "agentStatus", "chatPage",
            "chatAppend", "chatUpdate", "chatMeta", "pending", "ack", "pong", "error", "subagentList",
            "webServers",
        ]
        let chatItemTypes = [
            "userPrompt", "slashCommand", "assistantText", "thinking", "toolCall", "turnFooter", "recap", "notice",
            "unsupported", "workflow", "task",
        ]
        let expected = clientTypes.map { "client.\($0).json" }
            + serverTypes.map { "server.\($0).json" }
            + chatItemTypes.map { "chatItem.\($0).json" }
            + ["permission", "question"].map { "pendingRequest.\($0).json" }
            + ["allow", "deny", "answers"].map { "pendingResponse.\($0).json" }
            + ["client.openChat", "client.closeChat", "server.chatPage", "server.chatAppend"].map { "\($0).session.json" }
            + ["server.usage.noPlan.json", "server.tree.home.json"]
        let subagentStates: [String] = ["running", "completed", "failed", "stopped"]
        let subagentTargets: [String] = [
            "client.openChat", "client.closeChat", "server.chatPage", "server.chatUpdate", "server.chatMeta",
        ]
        let subagentPhase: [String] = subagentStates.map { "chatItem.subagent.\($0).json" }
            + subagentTargets.map { "\($0).subagent.json" }
            + ["server.tree.subagents.json"]
        let imagesPhase = [
            "chatItem.userPrompt.imagePaths.json", "chatItem.assistantText.imagePaths.json",
            "chatItem.toolCall.read-image.json",
        ]

        let alertsPhase = ["client.registerLiveActivity.ended.json"]

        for name in expected + subagentPhase + imagesPhase + alertsPhase {
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

    static let imageItems = [
        #"{"id":"8f2e…","at":"2026-09-25T15:46:02.000Z","type":"userPrompt","text":"olha o print","imageCount":1,"imagePaths":["/Users/joaoalves/Library/Application Support/Mocha/uploads/0B7C1E2A-5D4F-4A8B-9C3E-2F1A6B7C8D9E.jpg"]}"#,
    ]

    static let subagentItems = [
        #"{"id":"e4b1…","at":"2026-09-26T13:52:10.000Z","type":"subagent","toolUseId":"toolu_01AG…","agentId":"a0123456789abcdef","agentType":"general-purpose","description":"Teste de carga /receitas","status":"running","activity":{"toolName":"Bash","summary":"k6 run --vus 50 --duration 2m load/list-recipes.js","status":"running"},"toolUses":9,"startedAt":"2026-09-26T13:52:11.000Z"}"#,
        #"{"id":"f5c2…","at":"2026-09-26T13:50:02.000Z","type":"subagent","toolUseId":"toolu_01PL…","agentId":"a89abcdef01234567","agentType":"Plan","description":"Revisar o índice de receitas","status":"failed","toolUses":3,"startedAt":"2026-09-26T13:50:03.000Z","durationMs":48000,"failureReason":"Agent terminated early due to an API error: …"}"#,
        #"{"id":"0a7d…","at":"2026-09-26T14:10:00.000Z","type":"workflow","toolUseId":"toolu_01WF…","runId":"wf_0a1b2c3d-4e5","name":"auditoria-a11y","status":"running","phases":[{"title":"Mapear telas","status":"completed","agents":[{"agentId":"a1111111111111111","label":"Mapear","status":"completed","durationMs":95000}]},{"title":"Corrigir por tela","detail":"uma tela por agente, com testes de UI","status":"running","agents":[{"agentId":"a2222222222222222","label":"Ajustes","status":"running","activity":{"toolName":"Edit","summary":"SettingsView.swift","status":"running"}}]},{"title":"Revisar","status":"pending","agents":[]}],"agentCount":5,"toolUses":86,"startedAt":"2026-09-26T14:10:00.000Z"}"#,
        #"{"id":"1b8e…","at":"2026-09-26T13:52:11.000Z","type":"task","text":"Rode o teste de carga de GET /receitas com o k6 (load/list-recipes.js)…"}"#,
    ]

    static let all: [CanonicalExample] = [
        CanonicalExample(fixture: "chatItem.userPrompt.json", json: chatPageItems[0]),
        CanonicalExample(fixture: "chatItem.assistantText.json", json: chatPageItems[1]),
        CanonicalExample(fixture: "chatItem.toolCall.json", json: chatPageItems[2]),
        CanonicalExample(fixture: "chatItem.turnFooter.json", json: chatPageItems[3]),
        CanonicalExample(fixture: "chatItem.slashCommand.json", json: chatPageItems[4]),
        CanonicalExample(fixture: "chatItem.userPrompt.imagePaths.json", json: imageItems[0]),
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
        CanonicalExample(fixture: "chatItem.subagent.running.json", json: subagentItems[0]),
        CanonicalExample(fixture: "chatItem.subagent.failed.json", json: subagentItems[1]),
        CanonicalExample(fixture: "chatItem.workflow.json", json: subagentItems[2]),
        CanonicalExample(fixture: "chatItem.task.json", json: subagentItems[3]),
        CanonicalExample(
            fixture: "client.openChat.subagent.json",
            json: #"{"v":1,"id":"c-12","type":"openChat","payload":{"sessionId":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64","subagentId":"a0123456789abcdef","limit":60}}"#
        ),
        CanonicalExample(
            fixture: "server.chatMeta.subagent.json",
            json: #"{"v":1,"type":"chatMeta","payload":{"sessionId":"0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64","subagentId":"a0123456789abcdef","meta":{"title":"Teste de carga /receitas","workspaceLabel":"receitas-api","model":"claude-opus-5-5","branch":"development","status":"unknown","subagent":{"parentTitle":"Paginação com cursor em /receitas","agentType":"general-purpose","status":"completed","startedAt":"2026-09-26T13:52:11.000Z","durationMs":231000,"toolUses":12}}}}"#
        ),
        CanonicalExample(
            fixture: "client.listSubagents.json",
            json: #"{"v":1,"id":"c-13","type":"listSubagents","payload":{"agentId":"w17:p1"}}"#
        ),
        CanonicalExample(
            fixture: "server.subagentList.json",
            json: #"{"v":1,"id":"c-13","type":"subagentList","payload":{"agentId":"w17:p1","items":[{"agentId":"a0123456789abcdef","agentType":"general-purpose","description":"Teste de carga /receitas","status":"running","toolUses":9,"startedAt":"2026-09-26T13:52:11.000Z"},{"agentId":"a76543210fedcba98","parentAgentId":"a0123456789abcdef","agentType":"Explore","description":"Achar o script de carga","status":"completed","toolUses":5,"startedAt":"2026-09-26T13:52:20.000Z","durationMs":41000}]}}"#
        ),
        CanonicalExample(
            fixture: "server.helloOk.ssh.json",
            json: #"{"v":1,"id":"c-1","type":"helloOk","payload":{"host":{"hostName":"MacBook Pro de João","daemonVersion":"0.1.0","herdrConnected":true,"sshUser":"joaoalves","sshHostKeys":["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMochaHostKeyExampleOnlyForFixturesAAAAAAA","ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMochaExample"]},"deviceId":"0F8E2B6A-3C1D-4E5F-9A7B-8C6D5E4F3A2B","preferences":{"turnDoneAlerts":true}}}"#
        ),
        CanonicalExample(
            fixture: "client.listWebServers.json",
            json: #"{"v":1,"id":"c-21","type":"listWebServers","payload":{}}"#
        ),
        CanonicalExample(
            fixture: "server.webServers.json",
            json: #"{"v":1,"id":"c-21","type":"webServers","payload":{"host":"MacBook","servers":[{"pid":53243,"process":"node","port":5190,"title":"Portal do cliente","directory":"/Users/joaoalves/Developer/portal-cliente","workspaceId":"w1"},{"pid":5335,"process":"node","port":6173}]}}"#
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
