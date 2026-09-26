import Foundation
import Testing
@testable import MochaDaemonCore

enum HookFixtures {
    static let optionalFields = ["model", "prompt_id", "title", "scratchpad_dir", "permission_suggestions", "agent_id", "agent_type"]

    static func requests() throws -> [(name: HookEventName, file: String)] {
        let files = try FileManager.default.contentsOfDirectory(atPath: Fixtures.url("hooks").path(percentEncoded: false))
        return files.sorted().compactMap { file in
            guard file.hasSuffix(".json") else { return nil }
            let prefix = String(file.prefix { $0 != "." })
            return HookEventName(rawValue: prefix).map { (name: $0, file: file) }
        }
    }

    static func body(_ file: String, removing keys: [String] = [], adding extra: [String: Any] = [:]) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: Fixtures.data("hooks/\(file)")) as? [String: Any])
        for key in keys {
            object.removeValue(forKey: key)
        }
        object.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

@Suite
struct HookPayloadTests {
    @Test func everyRequestFixtureOfTheMochaEventsDecodes() throws {
        let requests = try HookFixtures.requests()

        #expect(Set(requests.map(\.name)) == Set(HookEventName.allCases))
        #expect(requests.count == 12)
        for request in requests {
            let event = try HookEvent.decode(request.name, from: Fixtures.data("hooks/\(request.file)"))
            #expect(event.name == request.name, "\(request.file)")
            #expect(event.context.transcriptPath?.hasSuffix("\(event.context.sessionId).jsonl") == true, "\(request.file)")
            #expect(event.context.cwd == "/Users/dev/projects/demo-app", "\(request.file)")
        }
    }

    @Test func everyRequestFixtureDecodesWithoutTheOptionalFields() throws {
        for request in try HookFixtures.requests() {
            let full = try HookEvent.decode(request.name, from: Fixtures.data("hooks/\(request.file)"))
            let trimmed = try HookEvent.decode(request.name, from: HookFixtures.body(request.file, removing: HookFixtures.optionalFields))

            #expect(trimmed.name == full.name, "\(request.file)")
            #expect(trimmed.context.sessionId == full.context.sessionId, "\(request.file)")
            #expect(trimmed.context.promptId == nil, "\(request.file)")
        }
    }

    @Test func sessionStartDistinguishesClearFromCompactAndKeepsTheMissingTranscript() throws {
        guard case .sessionStart(let clear) = try HookEvent.decode(.sessionStart, from: Fixtures.data("hooks/SessionStart.clear.json")),
              case .sessionStart(let compact) = try HookEvent.decode(.sessionStart, from: Fixtures.data("hooks/SessionStart.compact.json")),
              case .sessionStart(let startup) = try HookEvent.decode(.sessionStart, from: Fixtures.data("hooks/SessionStart.startup.json")),
              case .sessionStart(let resume) = try HookEvent.decode(.sessionStart, from: Fixtures.data("hooks/SessionStart.resume.json"))
        else {
            Issue.record("SessionStart não decodificou como sessionStart")
            return
        }

        #expect(clear.source == .clear)
        #expect(clear.model == nil)
        #expect(compact.source == .compact)
        #expect(compact.model == "claude-haiku-4-5-20251001")
        #expect(compact.context.promptId == "5f0c0000-0000-4000-8000-000000000001")
        #expect(clear.context.sessionId == compact.context.sessionId)
        #expect(startup.source == .startup)
        #expect(resume.source == .resume)
        let transcript = try #require(clear.context.transcriptPath)
        #expect(FileManager.default.fileExists(atPath: transcript) == false)
        #expect(SessionStartSource(rawValue: "fork") == .fork)
        #expect(SessionStartSource(rawValue: "novo") == .other("novo"))
    }

    @Test func eventFieldsComeFromThePayload() throws {
        guard case .userPromptSubmit(let prompt) = try HookEvent.decode(.userPromptSubmit, from: Fixtures.data("hooks/UserPromptSubmit.json")),
              case .stop(let stop) = try HookEvent.decode(.stop, from: Fixtures.data("hooks/Stop.json")),
              case .notification(let idle) = try HookEvent.decode(.notification, from: Fixtures.data("hooks/Notification.idle_prompt.json")),
              case .notification(let permission) = try HookEvent.decode(.notification, from: Fixtures.data("hooks/Notification.permission_prompt.json")),
              case .permissionRequest(let bash) = try HookEvent.decode(.permissionRequest, from: Fixtures.data("hooks/PermissionRequest.bash.json")),
              case .permissionRequest(let question) = try HookEvent.decode(.permissionRequest, from: Fixtures.data("hooks/PermissionRequest.AskUserQuestion.multi.json"))
        else {
            Issue.record("um dos fixtures não decodificou no evento certo")
            return
        }

        #expect(prompt.prompt == "Responda apenas com a palavra: pronto")
        #expect(prompt.context.promptId == "5f0c0000-0000-4000-8000-000000000004")
        #expect(prompt.context.permissionMode == "default")
        #expect(stop.lastAssistantMessage == "pronto")
        #expect(idle.kind == .idlePrompt)
        #expect(idle.message == "Claude is waiting for your input")
        #expect(idle.title == nil)
        #expect(permission.kind == .permissionPrompt)
        #expect(bash.toolName == "Bash")
        #expect(bash.toolInput == .object([
            OrderedJSON.Member("command", .string("touch f.txt")),
            OrderedJSON.Member("description", .string("Create an empty file named f.txt")),
        ]))
        #expect(question.toolName == "AskUserQuestion")
        #expect(question.toolInput["questions"]?.arrayValue?.count == 3)
        #expect(question.toolInput["questions"]?.arrayValue?[1]["multiSelect"] == .bool(true))
    }

    @Test func optionalFieldsAreReadWhenPresentAndUnknownFieldsAreIgnored() throws {
        let body = try HookFixtures.body("Notification.permission_prompt.json", adding: [
            "title": "Permissão",
            "agent_id": "a1b2",
            "agent_type": "Explore",
            "campo_novo": ["qualquer": 1],
        ])
        guard case .notification(let notification) = try HookEvent.decode(.notification, from: body) else {
            Issue.record("Notification não decodificou")
            return
        }

        #expect(notification.title == "Permissão")
        #expect(notification.context.subagentId == "a1b2")
        #expect(notification.context.subagentType == "Explore")
        #expect(NotificationKind(rawValue: "elicitation_dialog") == .elicitationDialog)
        #expect(NotificationKind(rawValue: "auth_success") == .other("auth_success"))
    }

    @Test func invalidPayloadsAreRejected() throws {
        #expect(throws: HookPayloadError.invalidJSON) {
            try HookEvent.decode(.stop, from: Data("{".utf8))
        }
        #expect(throws: HookPayloadError.notAnObject) {
            try HookEvent.decode(.stop, from: Data("[]".utf8))
        }
        #expect(throws: HookPayloadError.missingField("session_id")) {
            try HookEvent.decode(.stop, from: HookFixtures.body("Stop.json", removing: ["session_id"]))
        }
        #expect(throws: HookPayloadError.missingField("source")) {
            try HookEvent.decode(.sessionStart, from: HookFixtures.body("SessionStart.clear.json", removing: ["source"]))
        }
        #expect(throws: HookPayloadError.missingField("tool_input")) {
            try HookEvent.decode(.permissionRequest, from: HookFixtures.body("PermissionRequest.write.json", adding: ["tool_input": "texto"]))
        }
    }
}
