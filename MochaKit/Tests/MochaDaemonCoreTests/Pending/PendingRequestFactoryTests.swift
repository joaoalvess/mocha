import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite
struct PendingRequestFactoryTests {
    static func kind(_ file: String) throws -> PendingKind {
        PendingRequestFactory.kind(for: try PendingSample.permissionHook(file).request)
    }

    @Test func toolRequestsBecomePermissionsWithTheToolCallSummaryAndCompactInput() throws {
        #expect(try Self.kind("PermissionRequest.bash.json") == .permission(
            toolName: "Bash",
            summary: "touch f.txt",
            inputJSON: #"{"command":"touch f.txt","description":"Create an empty file named f.txt"}"#
        ))
        #expect(try Self.kind("PermissionRequest.write.json") == .permission(
            toolName: "Write",
            summary: "notas.md",
            inputJSON: #"{"file_path":"/Users/dev/projects/demo-app/notas.md","content":"teste"}"#
        ))
    }

    @Test func askUserQuestionBecomesAQuestionWithEveryOption() throws {
        guard case .question(let questions) = try Self.kind("PermissionRequest.AskUserQuestion.multi.json") else {
            Issue.record("not a question")
            return
        }
        #expect(questions.map(\.question) == ["Qual editor?", "Quais testes?", "Qual tema?"])
        #expect(questions.map(\.header) == ["Editor", "Testes", "Tema"])
        #expect(questions.map(\.multiSelect) == [false, true, false])
        #expect(questions[1].options == [
            PendingOption(label: "Unitários", description: "Testes Unitários"),
            PendingOption(label: "Integração", description: "Testes de Integração"),
            PendingOption(label: "UI", description: "Testes de UI"),
        ])
    }

    @Test func inputJSONIsTruncatedAt4000Characters() throws {
        let content = String(repeating: "é", count: 5_000)
        let body = Data(#"{"session_id":"s","cwd":"/tmp","tool_name":"Write","tool_input":{"file_path":"/tmp/a.txt","content":"\#(content)"}}"#.utf8)
        guard case .permissionRequest(let request) = try HookEvent.decode(.permissionRequest, from: body) else {
            Issue.record("not a permission request")
            return
        }
        guard case .permission(_, let summary, let inputJSON) = PendingRequestFactory.kind(for: request) else {
            Issue.record("not a permission")
            return
        }
        #expect(summary == "a.txt")
        #expect(inputJSON.count == 4_000)
        #expect(inputJSON.hasPrefix(#"{"file_path":"/tmp/a.txt","content":"éé"#))
    }

    @Test func compactSerializationKeepsTheOrderAndEscapes() throws {
        let json = try OrderedJSON.parse(Data(#"{"b": [1, true, null], "a": "linha\n\"x\"", "c": {}}"#.utf8))
        #expect(json.compactSerialized() == #"{"b":[1,true,null],"a":"linha\n\"x\"","c":{}}"#)
    }
}
