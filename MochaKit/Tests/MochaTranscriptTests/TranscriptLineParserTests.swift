import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

enum TranscriptLines {
    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func user(_ content: Any, uuid: String = UUID().uuidString, extra: [String: Any] = [:]) -> String {
        var object: [String: Any] = [
            "type": "user",
            "uuid": uuid,
            "timestamp": "2026-09-25T15:00:00.000Z",
            "message": ["role": "user", "content": content],
            "cwd": "/Users/dev/projects/demo-app",
            "version": "2.1.283",
        ]
        object.merge(extra) { $1 }
        return json(object)
    }

    static func assistant(
        _ blocks: [[String: Any]],
        uuid: String = UUID().uuidString,
        model: String = "claude-opus-5-5",
        branch: String = "main",
        extra: [String: Any] = [:]
    ) -> String {
        var object: [String: Any] = [
            "type": "assistant",
            "uuid": uuid,
            "timestamp": "2026-09-25T15:00:01.000Z",
            "message": ["model": model, "id": "msg_1", "role": "assistant", "content": blocks],
            "cwd": "/Users/dev/projects/demo-app",
            "gitBranch": branch,
            "version": "2.1.283",
        ]
        object.merge(extra) { $1 }
        return json(object)
    }

    static func toolUse(_ name: String, id: String, input: [String: Any]) -> String {
        assistant([["type": "tool_use", "id": id, "name": name, "input": input]])
    }

    static func toolResult(_ id: String, content: Any, isError: Bool? = nil, extra: [String: Any] = [:]) -> String {
        var block: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": content]
        if let isError { block["is_error"] = isError }
        return user([block], extra: extra)
    }

    static func system(_ subtype: String, content: String? = nil, extra: [String: Any] = [:]) -> String {
        var object: [String: Any] = [
            "type": "system",
            "subtype": subtype,
            "uuid": UUID().uuidString,
            "timestamp": "2026-09-25T15:00:02.000Z",
        ]
        if let content { object["content"] = content }
        object.merge(extra) { $1 }
        return json(object)
    }

    static func document(_ lines: [String]) -> TranscriptDocument {
        TranscriptDocument(bytes: Array((lines.joined(separator: "\n") + "\n").utf8))
    }
}

@Suite
struct TranscriptLineParserTests {
    private typealias L = TranscriptLines

    private func onlyItem(_ lines: [String]) throws -> ChatItemKind {
        let document = L.document(lines)
        #expect(document.items.count == 1)
        return try #require(document.items.first?.kind)
    }

    private func toolCall(_ lines: [String]) throws -> ToolCall {
        guard case .toolCall(let call) = try onlyItem(lines) else {
            Issue.record("não é toolCall")
            throw CancellationError()
        }
        return call
    }

    @Test func summariesFollowTheToolTable() throws {
        #expect(try toolCall([L.toolUse("Read", id: "t1", input: ["file_path": "/Users/dev/projects/demo-app/src/a.ts"])]).summary == "src/a.ts")
        #expect(try toolCall([L.toolUse("Edit", id: "t1", input: ["file_path": "/tmp/fora.ts"])]).summary == "/tmp/fora.ts")
        #expect(try toolCall([L.toolUse("NotebookEdit", id: "t1", input: ["notebook_path": "/Users/dev/projects/demo-app/n.ipynb"])]).summary == "n.ipynb")
        #expect(try toolCall([L.toolUse("Bash", id: "t1", input: ["command": "\nnpm test\nnpm run lint"])]).summary == "npm test")
        #expect(try toolCall([L.toolUse("Grep", id: "t1", input: ["pattern": "TODO", "path": "src"])]).summary == "TODO")
        #expect(try toolCall([L.toolUse("WebSearch", id: "t1", input: ["query": "swift testing"])]).summary == "swift testing")
        #expect(try toolCall([L.toolUse("Agent", id: "t1", input: ["prompt": "longo", "description": "Revisar"])]).summary == "Revisar")
        #expect(try toolCall([L.toolUse("AskUserQuestion", id: "t1", input: ["questions": [["question": "Qual?", "header": "Q"]]])]).summary == "Qual?")
        #expect(try toolCall([L.toolUse("ExitPlanMode", id: "t1", input: ["plan": "\n\n# Plano\n- passo"])]).summary == "# Plano")
        #expect(try toolCall([L.toolUse("Skill", id: "t1", input: ["skill": "pdf", "args": "x"])]).summary == "pdf")
        #expect(try toolCall([L.toolUse("TaskStop", id: "t1", input: ["task_id": "bk1"])]).summary == "bk1")
        #expect(try toolCall([L.toolUse("EnterPlanMode", id: "t1", input: [:])]).summary == "")
        let long = String(repeating: "x", count: 300)
        #expect(try toolCall([L.toolUse("Bash", id: "t1", input: ["command": long])]).summary.count == 120)
    }

    @Test func genericSummaryUsesTheFirstStringInInputOrder() throws {
        let line = #"{"type":"assistant","uuid":"u1","timestamp":"2026-09-25T15:00:01.000Z","message":{"model":"m","content":[{"type":"tool_use","id":"t1","name":"mcp__x__y","input":{"limit":3,"zeta":"primeiro","alpha":"segundo"}}]}}"#
        let call = try toolCall([line])
        #expect(call.summary == "primeiro")
        #expect(call.inputJSON == #"{"limit":3,"zeta":"primeiro","alpha":"segundo"}"#)
    }

    @Test func inputJSONIsTruncatedAtFourThousandCharacters() throws {
        let call = try toolCall([L.toolUse("Write", id: "t1", input: ["file_path": "a", "content": String(repeating: "é", count: 5_000)])])
        #expect(call.inputJSON.count == 4_000)
        #expect(call.status == .running)
        #expect(call.resultPreview == nil)
    }

    @Test func toolResultsResolveStatusAndPreview() throws {
        let document = L.document([
            L.toolUse("Bash", id: "t1", input: ["command": "ls"]),
            L.toolUse("Read", id: "t2", input: ["file_path": "a"]),
            L.toolUse("mcp__docs__search", id: "t3", input: ["query": "q"]),
            L.toolResult("t2", content: [
                ["type": "text", "text": "linha"],
                ["type": "image", "source": ["type": "base64", "data": "AAAA"]],
                ["type": "tool_reference", "tool_name": "WebFetch"],
                ["type": "document", "source": [:]],
                ["type": "outro"],
            ]),
            L.toolResult("t1", content: "Exit code 1", isError: true),
            L.toolResult("t3", content: String(repeating: "r", count: 2_500), isError: false),
            L.toolResult("desconhecido", content: "órfão"),
        ])
        let calls = document.items.compactMap { item -> ToolCall? in
            if case .toolCall(let call) = item.kind { return call }
            return nil
        }
        #expect(calls.map(\.status) == [.failed, .succeeded, .succeeded])
        #expect(calls[0].resultPreview == "Exit code 1")
        #expect(calls[1].resultPreview == "linha\n[imagem]\nWebFetch\n[documento]")
        #expect(calls[2].resultPreview?.count == 2_000)
        #expect(document.statistics.orphanResults == 1)
    }

    @Test func askUserQuestionPreviewListsAnswersInQuestionOrder() throws {
        let questions: [[String: Any]] = [
            ["question": "Quais testes?", "multiSelect": true],
            ["question": "Onde roda?", "multiSelect": false],
        ]
        let document = L.document([
            L.toolUse("AskUserQuestion", id: "t1", input: ["questions": questions]),
            L.toolResult("t1", content: "The user answered", extra: [
                "toolUseResult": [
                    "questions": questions,
                    "answers": ["Onde roda?": "Local", "Quais testes?": ["Unitários", "E2E"]],
                ],
            ]),
        ])
        guard case .toolCall(let call) = document.items.first?.kind else {
            Issue.record("sem toolCall")
            return
        }
        #expect(call.status == .succeeded)
        #expect(call.resultPreview == "Quais testes? → Unitários, E2E\nOnde roda? → Local")
    }

    @Test func localCommandsBecomeSlashCommandsWithCleanOutput() throws {
        let document = L.document([
            L.user("<command-name>/model</command-name>\n<command-message>model</command-message>\n<command-args> sonnet </command-args>", extra: ["promptId": "p1"]),
            L.user("<local-command-stdout>\n\u{1B}[1mSonnet 5\u{1B}[22m\n</local-command-stdout>", extra: ["promptId": "p1"]),
            L.user("<bash-input>git status</bash-input>"),
            L.user("<bash-stdout>  M a.swift\n</bash-stdout><bash-stderr>aviso</bash-stderr>"),
            L.system("local_command", content: "<command-name>/fast</command-name><command-args></command-args>"),
            L.system("local_command", content: "<local-command-stdout></local-command-stdout>"),
        ])
        #expect(document.items.map(\.kind) == [
            .slashCommand(name: "/model", args: "sonnet", output: "Sonnet 5"),
            .slashCommand(name: "!", args: "git status", output: "  M a.swift\naviso"),
            .slashCommand(name: "/fast", args: "", output: nil),
        ])
    }

    @Test func compactEchoWithSamePromptIdIsDeduplicated() throws {
        let document = L.document([
            L.user("/compact foco nos testes", extra: ["promptId": "p9"]),
            L.system("compact_boundary", content: "Conversation compacted"),
            L.user("<command-name>/compact</command-name><command-args>foco nos testes</command-args>", extra: ["promptId": "p9"]),
            L.user("<local-command-stdout>Compacted</local-command-stdout>", extra: ["promptId": "p9"]),
            L.user("<command-name>/compact</command-name>", extra: ["promptId": "p10"]),
        ])
        #expect(document.items.map(\.kind) == [
            .slashCommand(name: "/compact", args: "foco nos testes", output: "Compacted"),
            .notice(text: "Conversa compactada"),
            .slashCommand(name: "/compact", args: "", output: nil),
        ])
    }

    @Test func userLinesFollowTheRuleOrder() throws {
        let notification = "<task-notification>\n<summary>Agent \"Revisar\" finished</summary>\n</task-notification>"
        let document = L.document([
            L.user("caveat", extra: ["isMeta": true]),
            L.user("resumo", extra: ["isCompactSummary": true]),
            L.user(notification, extra: ["origin": ["kind": "task-notification"]]),
            L.user("texto qualquer", extra: ["origin": ["kind": "task-notification"]]),
            L.user([["type": "text", "text": "[Request interrupted by user]"]]),
            L.user([["type": "text", "text": "[Request interrupted by user for tool use]"]]),
            L.user([["type": "text", "text": "a"], ["type": "image", "source": [:]], ["type": "text", "text": "b"], ["type": "image", "source": [:]]]),
            L.user([["type": "text", "text": "com documento"], ["type": "document", "source": [:]]]),
            L.user("  Oi  "),
        ])
        #expect(document.items.map(\.kind) == [
            .notice(text: "Agent \"Revisar\" finished"),
            .notice(text: "texto qualquer"),
            .notice(text: "Interrompido pelo usuário"),
            .notice(text: "Interrompido pelo usuário"),
            .userPrompt(text: "a\nb", imageCount: 2),
            .userPrompt(text: "com documento", imageCount: 0),
            .userPrompt(text: "  Oi  ", imageCount: 0),
        ])
        #expect(document.statistics.unknown == ["block:document": 1])
    }

    @Test func assistantBlocksMapToItemsWithBlockIds() throws {
        let document = L.document([
            L.assistant([
                ["type": "thinking", "thinking": ""],
                ["type": "text", "text": "  \n"],
                ["type": "redacted_thinking", "data": "x"],
                ["type": "server_tool_use", "id": "s1"],
                ["type": "text", "text": "Olá"],
            ], uuid: "multi"),
            L.assistant([["type": "thinking", "thinking": "pensando"]], uuid: "single"),
            L.assistant([["type": "text", "text": "API Error: 529"]], uuid: "err", model: "<synthetic>", branch: "outra"),
        ])
        #expect(document.items.map(\.id) == ["multi#0", "multi#2", "multi#4", "single", "err"])
        #expect(document.items.map(\.kind) == [
            .thinking(text: nil),
            .thinking(text: nil),
            .assistantText(markdown: "Olá"),
            .thinking(text: "pensando"),
            .notice(text: "API Error: 529"),
        ])
        #expect(document.statistics.unknown == ["block:server_tool_use": 1])
        #expect(document.header.model == "claude-opus-5-5")
        #expect(document.header.branch == "main")
    }

    @Test func headerComesFromTheLastEntries() throws {
        let document = L.document([
            L.json(["type": "ai-title", "aiTitle": "Frase inicial"]),
            L.json(["type": "permission-mode", "permissionMode": "plan"]),
            L.assistant([["type": "text", "text": "a"]], model: "claude-haiku-4-5-20251001", branch: "feature/x"),
            L.json(["type": "ai-title", "aiTitle": "nome-kebab"]),
            L.assistant([["type": "text", "text": "b"]], model: "claude-opus-5-5", branch: "HEAD"),
            L.json(["type": "permission-mode", "permissionMode": "auto"]),
            L.json(["type": "mode", "mode": "normal", "version": "2.1.284"]),
        ])
        #expect(document.header == TranscriptHeader(
            title: "nome-kebab",
            model: "claude-opus-5-5",
            branch: nil,
            permissionMode: "auto",
            claudeVersion: "2.1.284",
            preview: MessagePreview(author: .assistant, text: "b"),
            sessionStartedAt: ProtocolDate.date(from: "2026-09-25T15:00:01.000Z")
        ))
    }

    @Test func systemSubtypesAndUnknownTypes() throws {
        let document = L.document([
            L.system("turn_duration", extra: ["durationMs": 45_000]),
            L.system("away_summary", content: "Resumo"),
            L.system("informational", content: "Aviso"),
            L.system("api_error", content: "Falhou"),
            L.system("model_consent_fallback", content: "Trocou"),
            L.system("stop_hook_summary"),
            L.system("bridge_status"),
            L.system("agents_killed"),
            L.system("nova_coisa", content: "?"),
            L.json(["type": "coisa-nova"]),
            L.json(["type": "worktree-state"]),
        ])
        #expect(document.items.map(\.kind) == [
            .turnFooter(durationMs: 45_000),
            .recap(text: "Resumo"),
            .notice(text: "Aviso"),
            .notice(text: "Falhou"),
            .notice(text: "Trocou"),
        ])
        #expect(document.statistics.unknown == ["subtype:nova_coisa": 1, "type:coisa-nova": 1])
    }

    @Test func queuedCommandsBecomePromptsOrNotices() throws {
        func attachment(_ fields: [String: Any], uuid: String) -> String {
            L.json(["type": "attachment", "uuid": uuid, "timestamp": "2026-09-25T15:00:00.000Z", "attachment": fields])
        }
        let document = L.document([
            attachment(["type": "queued_command", "commandMode": "prompt", "prompt": "digitado", "origin": ["kind": "human"]], uuid: "q1"),
            attachment(["type": "queued_command", "commandMode": "prompt", "prompt": [["type": "text", "text": "com print"], ["type": "image"]]], uuid: "q2"),
            attachment(["type": "queued_command", "commandMode": "prompt", "prompt": "vizinho", "origin": ["kind": "peer"]], uuid: "q3"),
            attachment(["type": "queued_command", "commandMode": "prompt", "prompt": "meta", "isMeta": true], uuid: "q4"),
            attachment(["type": "queued_command", "commandMode": "task-notification", "prompt": "<task-notification><summary>Build falhou</summary></task-notification>"], uuid: "q5"),
            attachment(["type": "environment"], uuid: "q6"),
        ])
        #expect(document.items.map(\.id) == ["q1", "q2", "q5"])
        #expect(document.items.map(\.kind) == [
            .userPrompt(text: "digitado", imageCount: 0),
            .userPrompt(text: "com print", imageCount: 1),
            .notice(text: "Build falhou"),
        ])
        #expect(document.statistics.unknown.isEmpty)
    }

    @Test func badLinesAreDroppedWithoutStoppingTheSession() throws {
        let bytes = Array((
            "{\"type\":\"user\"\n"
                + "\n"
                + "   \n"
                + "não é json\n"
                + "{\"sem\":\"type\"}\n"
                + "[1,2]\n"
                + L.user("lateral", extra: ["isSidechain": true]) + "\n"
                + L.user("válido") + "\n"
                + "{\"type\":\"user\",\"parcial"
        ).utf8)
        let document = TranscriptDocument(bytes: bytes)
        #expect(document.statistics.dropped == 4)
        #expect(document.items.map(\.kind) == [.userPrompt(text: "válido", imageCount: 0)])
        #expect(document.pendingByteCount == "{\"type\":\"user\",\"parcial".utf8.count)
    }

    @Test func timestampsFeedItemDates() throws {
        let document = L.document([L.user("oi")])
        #expect(document.items.first?.at == ProtocolDate.date(from: "2026-09-25T15:00:00.000Z"))
    }
}
