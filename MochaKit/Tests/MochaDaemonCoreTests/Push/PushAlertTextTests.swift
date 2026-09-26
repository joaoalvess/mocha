import Foundation
import Testing
@testable import MochaDaemonCore

struct PushAlertTextTests {
    static func request(_ toolName: String, _ input: String, cwd: String? = "/Users/dev/projects/demo-app") throws -> PermissionRequestHook {
        PermissionRequestHook(
            context: HookContext(sessionId: Sample.sessionA, cwd: cwd),
            toolName: toolName,
            toolInput: try OrderedJSON.parse(Data(input.utf8))
        )
    }

    @Test func titlesCarryTheWorkspaceWhenItIsKnown() {
        #expect(PushAlertText.title(.turnDone, workspaceLabel: "mocha") == "Claude terminou · mocha")
        #expect(PushAlertText.title(.needsInput, workspaceLabel: "mocha") == "Claude precisa de você · mocha")
        #expect(PushAlertText.title(.turnDone, workspaceLabel: nil) == "Claude terminou")
        #expect(PushAlertText.title(.needsInput, workspaceLabel: "  ") == "Claude precisa de você")
    }

    @Test func turnDoneBodyIsPlainTextWithAFallback() {
        #expect(PushAlertText.turnDoneBody("## Feito\n\nRodei `swift test` e **passou**.") == "Feito Rodei swift test e passou.")
        #expect(PushAlertText.turnDoneBody(nil) == "Turno concluído.")
        #expect(PushAlertText.turnDoneBody("   \n") == "Turno concluído.")
        #expect(PushAlertText.turnDoneBody(String(repeating: "a", count: 500)).count == 180)
    }

    @Test func needsInputBodyFollowsTheToolCallSummaryRule() throws {
        #expect(PushAlertText.needsInputBody(try Self.request("Bash", #"{"command": "\n  swift test\nswift build", "description": "Testes"}"#)) == "swift test")
        #expect(PushAlertText.needsInputBody(try Self.request("Write", #"{"file_path": "/Users/dev/projects/demo-app/notas.md", "content": "x"}"#)) == "notas.md")
        #expect(PushAlertText.needsInputBody(try Self.request("Edit", #"{"file_path": "/etc/hosts"}"#)) == "/etc/hosts")
        #expect(PushAlertText.needsInputBody(try Self.request("Grep", #"{"pattern": "TODO", "path": "src"}"#)) == "TODO")
        #expect(PushAlertText.needsInputBody(try Self.request("WebFetch", #"{"url": "https://example.com", "prompt": "p"}"#)) == "https://example.com")
        #expect(PushAlertText.needsInputBody(try Self.request("mcp__linear__save", #"{"count": 3, "title": "Nova tarefa", "body": "b"}"#)) == "Nova tarefa")
        #expect(PushAlertText.needsInputBody(try Self.request("mcp__x__y", #"{"count": 3}"#)) == "mcp__x__y")
        #expect(PushAlertText.needsInputBody(try Self.request("Bash", #"{"command": "\#(String(repeating: "x", count: 300))"}"#)).count == 120)
    }

    @Test func askUserQuestionUsesTheFirstQuestion() throws {
        let input = #"{"questions": [{"question": "Qual **banco**?", "header": "Banco"}, {"question": "Outra?"}]}"#
        #expect(PushAlertText.needsInputBody(try Self.request("AskUserQuestion", input)) == "Qual banco?")
        let request = try #require({ () throws -> PermissionRequestHook? in
            guard case .permissionRequest(let hook) = try PushHooks.fixture(.permissionRequest, "PermissionRequest.AskUserQuestion.multi.json") else { return nil }
            return hook
        }())
        #expect(!PushAlertText.needsInputBody(request).isEmpty)
    }
}
