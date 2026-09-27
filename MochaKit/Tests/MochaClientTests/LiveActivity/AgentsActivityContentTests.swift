import Foundation
import Testing
@testable import MochaClient

struct AgentsActivityContentTests {
    private static let permissionState = """
    {
      "working": 2,
      "waiting": 1,
      "highlight": {
        "agentId": "w17:p1",
        "title": "Modo escuro e RSS",
        "workspaceLabel": "site-pessoal",
        "status": "blocked",
        "since": 780000000.5
      },
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

    private static let questionState = """
    {
      "working": 0,
      "waiting": 1,
      "highlight": {
        "agentId": "w3:p2",
        "title": "Feed",
        "workspaceLabel": "blog",
        "status": "blocked",
        "since": 780000000
      },
      "pending": {
        "requestId": "5e3b0000-0000-4000-8000-000000000002",
        "agentId": "w3:p2",
        "kind": "question",
        "text": "Qual formato de feed você quer publicar?",
        "options": ["RSS 2.0", "Atom", "Os dois"]
      },
      "updatedAt": 780000040
    }
    """

    private static let moshiStyleState = """
    {
      "working": 1,
      "waiting": 0,
      "highlight": {
        "agentId": "w5:p2",
        "title": "Claude Code",
        "workspaceLabel": "mocha",
        "status": "working",
        "since": 780000000,
        "tabTitle": "M12",
        "model": "claude-opus-5-5",
        "contextLeftPercent": 89,
        "preview": "Comecei a 2.C, mas o WP-M12 ainda não está pronto",
        "activity": "Shell: npm run build"
      },
      "updatedAt": 780000060
    }
    """

    @Test func decodesTheMoshiStyleHighlightFields() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.moshiStyleState.utf8))
        #expect(content.highlight == AgentsActivityContent.Highlight(
            agentId: "w5:p2",
            title: "Claude Code",
            workspaceLabel: "mocha",
            status: "working",
            since: Date(timeIntervalSinceReferenceDate: 780_000_000),
            tabTitle: "M12",
            model: "claude-opus-5-5",
            contextLeftPercent: 89,
            preview: "Comecei a 2.C, mas o WP-M12 ainda não está pronto",
            activity: "Shell: npm run build"
        ))
        #expect(try JSONDecoder().decode(AgentsActivityContent.self, from: JSONEncoder().encode(content)) == content)
    }

    @Test func missingHighlightFieldsDecodeAsNilAndAreNotEncoded() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.permissionState.utf8))
        let highlight = try #require(content.highlight)
        #expect(highlight.tabTitle == nil)
        #expect(highlight.model == nil)
        #expect(highlight.contextLeftPercent == nil)
        #expect(highlight.preview == nil)
        #expect(highlight.activity == nil)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
        let encoded = try #require(object["highlight"] as? [String: Any])
        #expect(Set(encoded.keys) == ["agentId", "title", "workspaceLabel", "status", "since"])
    }

    @Test func decodesTheDaemonPermissionStateWithTheDefaultDecoder() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.permissionState.utf8))
        #expect(content.working == 2)
        #expect(content.waiting == 1)
        #expect(content.updatedAt == Date(timeIntervalSinceReferenceDate: 780_000_134.25))
        #expect(content.highlight == AgentsActivityContent.Highlight(
            agentId: "w17:p1",
            title: "Modo escuro e RSS",
            workspaceLabel: "site-pessoal",
            status: "blocked",
            since: Date(timeIntervalSinceReferenceDate: 780_000_000.5)
        ))
        #expect(content.pending == AgentsActivityContent.Pending(
            requestId: "5e3b0000-0000-4000-8000-000000000001",
            agentId: "w17:p1",
            kind: .permission,
            toolName: "Bash",
            text: "npm run build",
            options: []
        ))
    }

    @Test func decodesAQuestionWithOptionsAndNoToolName() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.questionState.utf8))
        let pending = try #require(content.pending)
        #expect(pending.kind == .question)
        #expect(pending.toolName == nil)
        #expect(pending.text == "Qual formato de feed você quer publicar?")
        #expect(pending.options == ["RSS 2.0", "Atom", "Os dois"])
        #expect(content.highlight?.since == Date(timeIntervalSinceReferenceDate: 780_000_000))
    }

    @Test func decodesTheFinalStateWithoutHighlightNorPending() throws {
        let json = #"{"working":0,"waiting":0,"updatedAt":780000200}"#
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(json.utf8))
        #expect(content == AgentsActivityContent(working: 0, waiting: 0, highlight: nil, updatedAt: Date(timeIntervalSinceReferenceDate: 780_000_200)))
        #expect(!content.isBusy)
    }

    @Test func pendingWithoutOptionsIsRejected() {
        let json = #"{"working":0,"waiting":1,"pending":{"requestId":"r","agentId":"a","kind":"question","text":"t"},"updatedAt":1}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentsActivityContent.self, from: Data(json.utf8))
        }
    }

    @Test func encodesDatesAsSecondsSinceReferenceDateLikeActivityKit() throws {
        let content = AgentsActivityContent(working: 1, waiting: 0, highlight: nil, updatedAt: Date(timeIntervalSinceReferenceDate: 42.5))
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
        #expect(object["updatedAt"] as? Double == 42.5)
        #expect(object["highlight"] == nil)
        #expect(object["pending"] == nil)
    }

    @Test func clearingPendingOnlyRemovesTheMatchingRequest() throws {
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: Data(Self.permissionState.utf8))
        #expect(content.clearingPending("outro") == nil)
        let cleared = try #require(content.clearingPending("5e3b0000-0000-4000-8000-000000000001"))
        #expect(cleared.pending == nil)
        #expect(cleared.working == content.working)
        #expect(cleared.waiting == content.waiting)
        #expect(cleared.highlight == content.highlight)
        #expect(cleared.updatedAt == content.updatedAt)
        var withoutPending = content
        withoutPending.pending = nil
        #expect(withoutPending.clearingPending("5e3b0000-0000-4000-8000-000000000001") == nil)
    }
}
