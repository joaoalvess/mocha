import Foundation
import MochaDaemonCore
import Testing
@testable import MochaClient

struct AgentsActivityContentTests {
    private static let permissionState = """
    {
      "agentId": "w17:p1",
      "title": "Modo escuro e RSS",
      "workspaceLabel": "site-pessoal",
      "status": "blocked",
      "since": 780000000.5,
      "prompt": "Faz dnv",
      "model": "claude-opus-5-5",
      "contextLeftPercent": 89,
      "pending": {
        "requestId": "5e3b0000-0000-4000-8000-000000000001",
        "agentId": "w17:p1",
        "kind": "permission",
        "toolName": "Bash",
        "text": "npm run build",
        "options": []
      },
      "updatedAt": 780000134.25
    }
    """

    @Test func decodesTheDaemonStateWithTheDefaultDecoderKeepingTheFocusedAgent() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.permissionState.utf8))
        #expect(content == AgentsActivityContent(
            agentId: "w17:p1",
            status: "blocked",
            title: "Modo escuro e RSS",
            workspaceLabel: "site-pessoal",
            since: Date(timeIntervalSinceReferenceDate: 780_000_000.5),
            model: "claude-opus-5-5",
            contextLeftPercent: 89,
            prompt: "Faz dnv",
            pending: .init(requestId: "5e3b0000-0000-4000-8000-000000000001", kind: .permission, toolName: "Bash", text: "npm run build", options: []),
            updatedAt: Date(timeIntervalSinceReferenceDate: 780_000_134.25)
        ))
        #expect(content.isBusy)
    }

    @Test func decodesWhatTheDaemonMirrorEncodes() throws {
        let since = Date(timeIntervalSinceReferenceDate: 780_000_000.75)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 780_000_100.5)
        let daemon = AgentActivityContentState(
            agent: .init(
                agentId: "w1:p4",
                title: "Refatora o parser",
                workspaceLabel: "mocha",
                status: "working",
                since: since,
                preview: "Rodando os testes",
                activity: "Bash: npm test",
                prompt: "Faz dnv"
            ),
            pending: .init(requestId: "req-1", agentId: "w1:p4", kind: .question, toolName: nil, text: "Qual banco?", options: ["Postgres", "SQLite"]),
            updatedAt: updatedAt
        )
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: JSONEncoder().encode(daemon))
        #expect(content == AgentsActivityContent(
            agentId: "w1:p4",
            status: "working",
            title: "Refatora o parser",
            workspaceLabel: "mocha",
            since: since,
            preview: "Rodando os testes",
            activity: "Bash: npm test",
            prompt: "Faz dnv",
            pending: .init(requestId: "req-1", kind: .question, toolName: nil, text: "Qual banco?", options: ["Postgres", "SQLite"]),
            updatedAt: updatedAt
        ))
    }

    @Test func missingOptionalFieldsDecodeAsNilAndAreNotEncoded() throws {
        let json = #"{"agentId":"w1:p1","status":"idle","title":"t","workspaceLabel":"w","since":1,"updatedAt":2}"#
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(json.utf8))
        #expect(!content.isBusy)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
        #expect(Set(object.keys) == ["agentId", "status", "title", "workspaceLabel", "since", "updatedAt"])
        #expect(object["updatedAt"] as? Double == 2)
    }

    @Test func pendingWithoutOptionsIsRejected() {
        let json = #"{"agentId":"w1:p1","status":"blocked","title":"t","workspaceLabel":"w","since":1,"pending":{"requestId":"r","kind":"question","text":"t"},"updatedAt":1}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentsActivityContent.self, from: Data(json.utf8))
        }
    }

    @Test func stateWithoutTheFocusedAgentIsRejected() {
        let json = #"{"status":"working","title":"t","workspaceLabel":"w","since":1,"updatedAt":1}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentsActivityContent.self, from: Data(json.utf8))
        }
    }

    @Test func clearingPendingOnlyRemovesTheMatchingRequest() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.permissionState.utf8))
        #expect(content.clearingPending("outro", outcome: .allowed) == nil)
        let cleared = try #require(content.clearingPending("5e3b0000-0000-4000-8000-000000000001", outcome: .allowed))
        var expected = content
        expected.pending = nil
        expected.outcome = "allowed"
        #expect(cleared == expected)
        #expect(expected.clearingPending("5e3b0000-0000-4000-8000-000000000001", outcome: .allowed) == nil)
        #expect(try #require(content.clearingPending("5e3b0000-0000-4000-8000-000000000001", outcome: nil)).outcome == nil)
    }
}
