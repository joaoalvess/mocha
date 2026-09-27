import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaTranscript

@Suite
struct SubagentCardTests {
    private typealias L = TranscriptLines
    private typealias N = NotificationLines

    @Test func agentAndTaskBecomeRunningCardsWithTheDisplayType() {
        let document = L.document([
            L.toolUse("Agent", id: "t1", input: ["description": "Revisar", "subagent_type": "feature-dev:code-reviewer", "prompt": "x"]),
            L.toolUse("Task", id: "t2", input: ["description": "Antigo", "prompt": "x"]),
            L.toolUse("Agent", id: "t3", input: ["description": "Vazio", "subagent_type": "", "prompt": "x"]),
        ])
        #expect(N.subagents(document) == [
            SubagentCall(toolUseId: "t1", agentType: "code-reviewer", description: "Revisar", status: .running),
            SubagentCall(toolUseId: "t2", agentType: "general-purpose", description: "Antigo", status: .running),
            SubagentCall(toolUseId: "t3", agentType: "general-purpose", description: "Vazio", status: .running),
        ])
        #expect(document.header.activity == nil)
        #expect(SubagentType.displayName(for: "plugin:sub:reviewer") == "reviewer")
        #expect(SubagentType.displayName(for: "Explore") == "Explore")
    }

    @Test func toolResultsFillTheCard() throws {
        let document = L.document([
            L.toolUse("Agent", id: "sync", input: ["description": "Síncrono", "prompt": "x"]),
            L.toolResult("sync", content: [["type": "text", "text": "Pronto."]], extra: ["toolUseResult": [
                "status": "completed", "agentId": N.agentId, "totalToolUseCount": 3, "totalDurationMs": 4_100,
            ]]),
            L.toolUse("Agent", id: "erro", input: ["description": "Com erro", "prompt": "x"]),
            L.toolResult("erro", content: "Agent type 'x' not found", isError: true),
        ] + N.agentLaunch(toolUseId: "async", agentId: N.otherAgentId))
        #expect(N.subagents(document) == [
            SubagentCall(toolUseId: "sync", agentId: N.agentId, agentType: "general-purpose", description: "Síncrono", status: .completed, toolUses: 3, durationMs: 4_100),
            SubagentCall(toolUseId: "erro", agentType: "general-purpose", description: "Com erro", status: .failed, failureReason: "Agent type 'x' not found"),
            SubagentCall(toolUseId: "async", agentId: N.otherAgentId, agentType: "general-purpose", description: "Revisar README", status: .running),
        ])
        #expect(document.statistics.orphanResults == 0)
    }

    @Test func workflowCardTakesItsNameFromTheScriptThePathOrTheFallback() throws {
        let script = "export const meta = { name: 'do-script', phases: [{ title: 'A' }] }"
        let document = L.document([
            L.toolUse("Workflow", id: "w1", input: ["script": script]),
            L.toolUse("Workflow", id: "w2", input: ["script": "sem meta", "scriptPath": "/x/scripts/do-arquivo-wf_0a1b2c3d-4e5.js"]),
            L.toolUse("Workflow", id: "w3", input: ["args": [:]]),
            L.toolResult("w3", content: "falhou", isError: true),
        ])
        let cards = N.workflows(document)
        #expect(cards.map(\.name) == ["do-script", "do-arquivo", "Workflow"])
        #expect(cards.map(\.status) == [.running, .running, .failed])
        #expect(cards[0].phases.isEmpty)
        #expect(cards[0].startedAt == ProtocolDate.date(from: "2026-09-25T15:00:01.000Z"))
    }

    @Test func workflowLaunchReplacesTheNameAndKeepsTheRunId() throws {
        let card = try #require(N.workflows(L.document(N.workflowLaunch(toolUseId: "w"))).first)
        #expect(card.name == "onda-1")
        #expect(card.runId == "wf_0a1b2c3d-4e5")
        #expect(card.status == .running)
    }
}

@Suite
struct SubagentModeTests {
    private typealias L = TranscriptLines
    private typealias N = NotificationLines
    private static let subagent = TranscriptParseMode.subagent(forkToolUseId: nil)

    private func document(_ lines: [String], mode: TranscriptParseMode) -> TranscriptDocument {
        TranscriptDocument(bytes: Array((lines.joined(separator: "\n") + "\n").utf8), mode: mode)
    }

    @Test func rootLineBecomesTheTaskAndSidechainLinesAreAccepted() {
        let lines = [
            L.user("Revise o README.", uuid: "raiz", extra: ["parentUuid": NSNull(), "isSidechain": true]),
            L.user("<system-reminder>handback</system-reminder>", extra: ["parentUuid": "raiz", "isSidechain": true, "isMeta": true]),
            L.assistant([["type": "text", "text": "Feito."]], uuid: "texto", extra: ["isSidechain": true]),
            L.system("turn_duration", extra: ["durationMs": 900, "isSidechain": true]),
        ]
        let subagent = document(lines, mode: Self.subagent)
        #expect(subagent.items.map(\.id) == ["raiz", "texto"])
        #expect(subagent.items.map(\.kind) == [.task(text: "Revise o README."), .assistantText(markdown: "Feito.")])
        #expect(subagent.header.model == "claude-opus-5-5")
        #expect(document(lines, mode: .main).items.isEmpty)
    }

    @Test func nestedAgentBecomesASubagentCard() {
        let lines = [L.user("Tarefa.", extra: ["parentUuid": NSNull(), "isSidechain": true])]
            + N.agentLaunch(toolUseId: "aninhado", type: "Explore")
        let cards = N.subagents(document(lines, mode: Self.subagent))
        #expect(cards.map(\.agentType) == ["Explore"])
        #expect(cards.map(\.agentId) == [N.agentId])
    }

    @Test func forkSkipsEverythingUntilTheBoundaryAndReadsTheDirective() {
        let copied = [
            L.json(["type": "fork-context-ref", "agentId": N.agentId, "parentSessionId": "s", "contextLength": 10]),
            L.user("Tarefa do pai.", extra: ["parentUuid": NSNull(), "isSidechain": true]),
            L.toolUse("Agent", id: "fork", input: ["description": "Fork", "subagent_type": "fork", "prompt": "Investigue."]),
        ]
        let boundary = L.user([
            ["type": "tool_result", "tool_use_id": "fork", "content": "Fork started — processing in background…"],
            ["type": "text", "text": "<fork-boilerplate>\nregras\n</fork-boilerplate>\n\nYour directive: Investigue o ramo B."],
        ], uuid: "fronteira")
        let after = L.assistant([["type": "text", "text": "Pronto."]])
        let fork = document(copied + [boundary, after], mode: .subagent(forkToolUseId: "fork"))
        #expect(fork.items.map(\.id).first == "fronteira")
        #expect(fork.items.map(\.kind) == [.task(text: "Investigue o ramo B."), .assistantText(markdown: "Pronto.")])

        let withoutMarker = L.user([
            ["type": "tool_result", "tool_use_id": "fork", "content": "ok"],
            ["type": "text", "text": "Diretiva inteira."],
        ])
        #expect(document(copied + [withoutMarker], mode: .subagent(forkToolUseId: "fork")).items.map(\.kind) == [.task(text: "Diretiva inteira.")])
        #expect(document(copied + [after], mode: .subagent(forkToolUseId: "fork")).items.isEmpty)
    }

    @Test(arguments: TranscriptFixtures.subagentNames)
    func pagesMatchTheDocument(_ name: String) throws {
        let document = try TranscriptFixtures.document(name)
        let reader = try TranscriptPageReader(path: TranscriptFixtures.path(name), mode: try TranscriptFixtures.mode(name))
        var slice = try reader.lastPage(limit: 2)
        var pages = [slice.items]
        while slice.hasMore, let offset = slice.firstLineOffset {
            slice = try #require(try reader.page(beforeOffset: offset, limit: 2))
            pages.insert(slice.items, at: 0)
        }
        #expect(pages.flatMap { $0 } == document.items)
        #expect(document.items.first.map { if case .task = $0.kind { true } else { false } } == true)
    }

    @Test(arguments: TranscriptFixtures.subagentNames)
    func followerMatchesTheDocumentFromAnySplit(_ name: String) throws {
        let mode = try TranscriptFixtures.mode(name)
        let document = try TranscriptFixtures.document(name)
        let bytes = try TranscriptFixtures.bytes(name)
        let lineEnds = bytes.indices.filter { bytes[$0] == 0x0A }.map { $0 + 1 }
        for split in [0, 1, 3, lineEnds.count / 2, lineEnds.count] {
            let cut = split == 0 ? 0 : lineEnds[split - 1]
            let transcript = try TemporaryTranscript(contents: Array(bytes[..<cut]))
            let follower = try TranscriptFollower(path: transcript.path, start: .afterExistingLines, mode: mode)
            var list = ChatItemList(try follower.lastPage(limit: 1_000).items)
            for chunk in ChunkPlan.chunks(of: Array(bytes[cut...])) {
                try transcript.append(chunk)
                for change in try follower.readAppendedLines().changes {
                    list.apply(change)
                }
            }
            #expect(list.items == document.items, "\(name) cortado na linha \(split)")
        }
    }

    @Test func headerReadsTheSubagentModelOnlyInSubagentMode() throws {
        let path = TranscriptFixtures.path("subagents-background/subagents/agent-a2222222222222222")
        let header = try TranscriptHeaderScanner.header(ofFileAt: path, mode: Self.subagent)
        #expect(header.model == "claude-opus-5-5")
        #expect(header.branch == "main")
        #expect(try TranscriptHeaderScanner.header(ofFileAt: path).model == nil)
    }
}
