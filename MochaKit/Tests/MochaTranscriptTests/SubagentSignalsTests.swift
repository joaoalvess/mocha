import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaTranscript

@Suite struct SubagentSignalsTests {
    private static let background = "subagents-background/subagents/agent-"
    private static let workflow = "workflow/subagents/workflows/wf_0a1b2c3d-4e5/agent-"

    private func scan(_ name: String) throws -> SubagentFileScanner {
        let mode = try TranscriptFixtures.mode(name)
        var forkToolUseId: String?
        if case .subagent(let id) = mode {
            forkToolUseId = id
        }
        var scanner = SubagentFileScanner(forkToolUseId: forkToolUseId)
        let text = try String(contentsOf: TranscriptFixtures.url(name), encoding: .utf8)
        for line in text.split(separator: "\n") {
            scanner.consume(Array(line.utf8))
        }
        return scanner
    }

    @Test func endingsFollowTheLastLineThatIsNotAnAttachment() throws {
        #expect(try scan(Self.background + "a1111111111111111").ending == .completed)
        #expect(try scan(Self.background + "a2222222222222222").ending == .failed(reason: "API Error: 529 Overloaded. Try again in a few moments."))
        #expect(try scan(Self.background + "a3333333333333333").ending == .stopped)
        #expect(try scan(Self.background + "a4444444444444444").ending == .completed)
        #expect(try scan(Self.background + "a5555555555555555").ending == .completed)
        #expect(try scan(Self.background + "a6666666666666666").ending == .completed)
        #expect(try scan(Self.workflow + "a8888888888888888").ending == .completed)
        #expect(try scan(Self.workflow + "a9999999999999999").ending == .stopped)
        #expect(try scan(Self.workflow + "abbbbbbbbbbbbbbbb").ending == .completed)
    }

    @Test func forkMetricsStartAtTheBoundary() throws {
        let fork = try scan(Self.background + "a5555555555555555")
        let document = try TranscriptFixtures.document(Self.background + "a5555555555555555")
        let toolCalls = document.items.filter {
            if case .toolCall = $0.kind { return true }
            return false
        }
        #expect(fork.hasCrossedForkBoundary)
        #expect(fork.toolUses == toolCalls.count)
        #expect(fork.startedAt == document.items.first?.at)
    }

    @Test func pendingToolIsTheActivityWhileRunning() {
        var scanner = SubagentFileScanner(forkToolUseId: nil)
        scanner.consume(Array(TranscriptLines.toolUse("Bash", id: "toolu_1", input: ["command": "swift test"]).utf8))
        #expect(scanner.ending == .running)
        #expect(scanner.toolUses == 1)
        #expect(scanner.activity == ToolActivity(toolName: "Bash", summary: "swift test", status: .running))
        scanner.consume(Array(TranscriptLines.toolResult("toolu_1", content: "ok").utf8))
        #expect(scanner.activity == nil)
        #expect(scanner.ending == .running)
    }

    @Test func attachmentAfterTheEndKeepsTheEnding() throws {
        var scanner = try scan(Self.background + "a1111111111111111")
        let endingAt = scanner.endingAt
        scanner.consume(Array(TranscriptLines.json(["type": "attachment", "timestamp": "2026-09-26T23:00:00.000Z", "attachment": ["type": "prompt_snapshot"]]).utf8))
        #expect(scanner.ending == .completed)
        #expect(scanner.endingAt == endingAt)
        scanner.consume(Array(TranscriptLines.user("Continue", extra: ["origin": ["kind": "coordinator"]]).utf8))
        #expect(scanner.ending == .running)
    }

    @Test func mainTranscriptSignals() throws {
        let text = try String(contentsOf: TranscriptFixtures.url("subagents-background"), encoding: .utf8)
        let signals = text.split(separator: "\n").flatMap { SubagentSignalScanner.signals(in: Array($0.utf8)) }
        let enqueued = signals.compactMap { signal -> String? in
            guard case .notification(let notification, _, true) = signal else { return nil }
            return notification.taskId
        }
        let delivered = signals.compactMap { signal -> String? in
            guard case .notification(let notification, _, false) = signal else { return nil }
            return notification.taskId
        }
        #expect(enqueued.contains("a4444444444444444"))
        #expect(enqueued.contains("a2222222222222222"))
        #expect(!delivered.isEmpty)
        #expect(signals.allSatisfy { signal in
            guard case .notification(let notification, _, _) = signal else { return true }
            return notification.kind != .other
        })
    }

    @Test func workflowLaunchSignals() throws {
        let text = try String(contentsOf: TranscriptFixtures.url("workflow"), encoding: .utf8)
        let signals = text.split(separator: "\n").flatMap { SubagentSignalScanner.signals(in: Array($0.utf8)) }
        let launch = signals.first { if case .workflowLaunch = $0 { return true } else { return false } }
        let launched = signals.first { if case .workflowLaunched = $0 { return true } else { return false } }
        guard case .workflowLaunch(let toolUseId, let script, _, _) = launch else {
            Issue.record("no Workflow tool_use")
            return
        }
        #expect(script.flatMap(WorkflowScriptMeta.parse)?.phases.map(\.title) == ["Implementar", "Verificar"])
        guard case .workflowLaunched(let resultToolUseId, let runId, let taskId, _, _) = launched else {
            Issue.record("no Workflow tool_result")
            return
        }
        #expect(resultToolUseId == toolUseId)
        #expect(runId == "wf_0a1b2c3d-4e5")
        #expect(taskId == "wabc12345")
    }

    @Test func linesWithoutMarkersAreNotDecoded() {
        #expect(!SubagentSignalScanner.mayContainSignal(Array(TranscriptLines.user("oi").utf8)))
        #expect(SubagentSignalScanner.signals(in: Array("{not json task-notification".utf8)).isEmpty)
    }
}
