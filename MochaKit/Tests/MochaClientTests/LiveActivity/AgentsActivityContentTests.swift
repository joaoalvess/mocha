import Foundation
import MochaDaemonCore
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

    @Test func decodesWhatTheDaemonMirrorEncodes() throws {
        let since = Date(timeIntervalSinceReferenceDate: 780_000_000.75)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 780_000_100.5)
        let daemon = LiveActivityContentState(
            working: 3,
            waiting: 0,
            highlight: .init(agentId: "w1:p4", title: "Refatora o parser", workspaceLabel: "mocha", status: "working", since: since),
            updatedAt: updatedAt
        )
        let content = try JSONDecoder().decode(AgentsActivityContent.self, from: JSONEncoder().encode(daemon))
        #expect(content == AgentsActivityContent(
            working: 3,
            waiting: 0,
            highlight: .init(agentId: "w1:p4", title: "Refatora o parser", workspaceLabel: "mocha", status: "working", since: since),
            updatedAt: updatedAt
        ))
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
