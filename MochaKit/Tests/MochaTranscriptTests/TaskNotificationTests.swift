import Foundation
import MochaProtocol
import Testing
@testable import MochaTranscript

enum NotificationLines {
    typealias L = TranscriptLines

    static let agentId = "a0123456789abcdef"
    static let otherAgentId = "afedcba9876543210"

    static func block(
        taskId: String?,
        toolUseId: String? = nil,
        status: String = "completed",
        summary: String,
        note: String? = nil,
        result: String? = nil,
        usage: [(String, Int)] = []
    ) -> String {
        var parts = ["<task-notification>"]
        if let taskId { parts.append("<task-id>\(taskId)</task-id>") }
        if let toolUseId { parts.append("<tool-use-id>\(toolUseId)</tool-use-id>") }
        parts.append("<status>\(status)</status>")
        parts.append("<summary>\(summary)</summary>")
        if let note { parts.append("<note>\(note)</note>") }
        if let result { parts.append("<result>\(result)</result>") }
        if !usage.isEmpty {
            parts.append("<usage>" + usage.map { "<\($0.0)>\($0.1)</\($0.0)>" }.joined() + "</usage>")
        }
        parts.append("</task-notification>")
        return parts.joined(separator: "\n")
    }

    static func userNotification(_ text: String, uuid: String = UUID().uuidString, extra: [String: Any] = [:]) -> String {
        L.user(text, uuid: uuid, extra: ["origin": ["kind": "task-notification"]].merging(extra) { $1 })
    }

    static func attachmentNotification(_ text: String) -> String {
        L.json([
            "type": "attachment",
            "uuid": UUID().uuidString,
            "timestamp": "2026-09-25T15:00:03.000Z",
            "attachment": ["type": "queued_command", "commandMode": "task-notification", "prompt": text],
        ])
    }

    static func agentLaunch(
        toolUseId: String,
        agentId: String = agentId,
        description: String = "Revisar README",
        type: String? = "general-purpose",
        name: String = "Agent"
    ) -> [String] {
        var input: [String: Any] = ["description": description, "prompt": "Revise."]
        if let type { input["subagent_type"] = type }
        return [
            L.toolUse(name, id: toolUseId, input: input),
            L.toolResult(
                toolUseId,
                content: [["type": "text", "text": "Async agent launched successfully."]],
                extra: ["toolUseResult": ["isAsync": true, "status": "async_launched", "agentId": agentId]]
            ),
        ]
    }

    static func workflowLaunch(toolUseId: String, taskId: String = "wabc12345") -> [String] {
        [
            L.toolUse("Workflow", id: toolUseId, input: ["scriptPath": "/tmp/scripts/demo-wave-wf_0a1b2c3d-4e5.js", "args": [:]]),
            L.toolResult(
                toolUseId,
                content: [["type": "text", "text": "Workflow launched in background."]],
                extra: ["toolUseResult": [
                    "status": "async_launched",
                    "taskId": taskId,
                    "workflowName": "onda-1",
                    "runId": "wf_0a1b2c3d-4e5",
                ]]
            ),
        ]
    }

    static func subagents(_ document: TranscriptDocument) -> [SubagentCall] {
        document.items.compactMap {
            if case .subagent(let call) = $0.kind { return call }
            return nil
        }
    }

    static func workflows(_ document: TranscriptDocument) -> [WorkflowCall] {
        document.items.compactMap {
            if case .workflow(let call) = $0.kind { return call }
            return nil
        }
    }
}

@Suite
struct TaskNotificationTests {
    private typealias L = TranscriptLines
    private typealias N = NotificationLines

    @Test func parseReadsEveryFieldAndIgnoresTagsInsideTheResult() throws {
        let text = N.block(
            taskId: N.agentId,
            toolUseId: "toolu_1",
            summary: "Agent \"Revisar\" finished",
            note: "A task-notification fires each time this agent stops.",
            result: "<summary>falso</summary><usage><tool_uses>99</tool_uses></usage>",
            usage: [("subagent_tokens", 900), ("tool_uses", 12), ("duration_ms", 34_000)]
        )
        let notification = try #require(TaskNotification.parse(text).first)
        #expect(notification == TaskNotification(
            taskId: N.agentId,
            toolUseId: "toolu_1",
            status: "completed",
            summary: "Agent \"Revisar\" finished",
            note: "A task-notification fires each time this agent stops.",
            toolUses: 12,
            durationMs: 34_000
        ))
        #expect(notification.kind == .agent)
        #expect(notification.subagentStatus == .completed)
        #expect(!notification.isInterim)
    }

    @Test func parseSplitsBlocksAndClassifiesTaskIds() {
        let text = [
            N.block(taskId: N.agentId, summary: "a"),
            N.block(taskId: "wxbfia3jy", summary: "w", usage: [("agent_count", 4)]),
            N.block(taskId: "bk7q2m9xa", summary: "b"),
            N.block(taskId: nil, summary: "sem id"),
            N.block(taskId: "a0123", summary: "id curto"),
        ].joined(separator: "\n")
        let notifications = TaskNotification.parse(text)
        #expect(notifications.map(\.kind) == [.agent, .workflow, .other, .other, .other])
        #expect(notifications[1].agentCount == 4)
        #expect(TaskNotification.parse("2 background agents were stopped by the user: \"A\", \"B\".").isEmpty)
    }

    @Test func statusesMapToSubagentAndWorkflowStates() {
        let interim = TaskNotification(status: "completed", note: "This agent stopped with background work of its own still running, so …")
        #expect(interim.isInterim)
        #expect(interim.subagentStatus == .running)
        #expect(TaskNotification(status: "failed").subagentStatus == .failed)
        #expect(TaskNotification(status: "killed").subagentStatus == .stopped)
        #expect(TaskNotification(status: "killed").workflowStatus == .stopped)
        #expect(TaskNotification(status: "failed").workflowStatus == .failed)
        #expect(TaskNotification(status: "running").subagentStatus == nil)
        let failed = TaskNotification(status: "failed", summary: "Agent \"Checar: failed: x\" failed: Agent terminated early due to an API error: Overloaded")
        #expect(failed.failureReason == "Agent terminated early due to an API error: Overloaded")
        #expect(TaskNotification(status: "failed", summary: "Falhou sem marcador").failureReason == "Falhou sem marcador")
        #expect(TaskNotification(status: "completed", summary: "x failed: y").failureReason == nil)
    }

    @Test func agentNotificationWithToolUseIdCompletesTheCardWithoutAnItem() throws {
        let notification = N.block(
            taskId: N.agentId,
            toolUseId: "toolu_a",
            summary: "Agent \"Revisar README\" finished",
            usage: [("tool_uses", 7), ("duration_ms", 61_000)]
        )
        let document = L.document(N.agentLaunch(toolUseId: "toolu_a") + [N.userNotification(notification)])
        #expect(document.items.count == 1)
        let card = try #require(N.subagents(document).first)
        #expect(card.status == .completed)
        #expect(card.agentId == N.agentId)
        #expect(card.toolUses == 7)
        #expect(card.durationMs == 61_000)
        #expect(document.changes.last == .update(document.items[0]))
    }

    @Test func agentNotificationWithoutToolUseIdMatchesTheAgentId() throws {
        let notification = N.block(taskId: N.otherAgentId, summary: "Agent \"B\" finished", usage: [("tool_uses", 2), ("duration_ms", 900)])
        let document = L.document(
            N.agentLaunch(toolUseId: "toolu_a")
                + N.agentLaunch(toolUseId: "toolu_b", agentId: N.otherAgentId, description: "B")
                + [N.attachmentNotification(notification)]
        )
        let cards = N.subagents(document)
        #expect(cards.map(\.status) == [.running, .completed])
        #expect(cards[1].toolUses == 2)
    }

    @Test func interimNotificationKeepsTheCardRunningUntilTheFinalOne() throws {
        let interim = N.block(
            taskId: N.agentId,
            toolUseId: "toolu_a",
            summary: "Agent \"Revisar README\" finished",
            note: "This agent stopped with background work of its own still running, so the result below may be interim.",
            usage: [("tool_uses", 3), ("duration_ms", 5_000)]
        )
        let final = N.block(taskId: N.agentId, summary: "Agent \"Revisar README\" finished", usage: [("tool_uses", 5), ("duration_ms", 9_000)])
        let launch = N.agentLaunch(toolUseId: "toolu_a")
        let running = try #require(N.subagents(L.document(launch + [N.userNotification(interim)])).first)
        #expect(running.status == .running)
        #expect(running.durationMs == nil)
        let done = try #require(N.subagents(L.document(launch + [N.userNotification(interim), N.userNotification(final)])).first)
        #expect(done.status == .completed)
        #expect(done.toolUses == 5)
        #expect(done.durationMs == 9_000)
    }

    @Test func failedAndKilledNotificationsCloseTheCard() throws {
        let failed = N.block(
            taskId: N.agentId,
            toolUseId: "toolu_a",
            status: "failed",
            summary: "Agent \"Revisar README\" failed: Agent terminated early due to an API error: Overloaded (HTTP 529)"
        )
        let killed = N.block(taskId: N.otherAgentId, toolUseId: "toolu_b", status: "killed", summary: "Agent \"B\" was stopped by Claude")
        let document = L.document(
            N.agentLaunch(toolUseId: "toolu_a")
                + N.agentLaunch(toolUseId: "toolu_b", agentId: N.otherAgentId, description: "B")
                + [N.userNotification(failed), N.attachmentNotification(killed)]
        )
        let cards = N.subagents(document)
        #expect(cards.map(\.status) == [.failed, .stopped])
        #expect(cards[0].failureReason == "Agent terminated early due to an API error: Overloaded (HTTP 529)")
        #expect(cards[1].failureReason == nil)
        #expect(document.items.count == 2)
    }

    @Test func workflowNotificationClosesTheCardWithCounts() throws {
        let notification = N.block(
            taskId: "wabc12345",
            summary: "Dynamic workflow \"Onda 1\" completed",
            usage: [("agent_count", 4), ("agents_done", 4), ("subagent_tokens", 1), ("tool_uses", 80), ("duration_ms", 600_000)]
        )
        let document = L.document(N.workflowLaunch(toolUseId: "toolu_w") + [N.userNotification(notification)])
        let card = try #require(N.workflows(document).first)
        #expect(card.status == .completed)
        #expect(card.name == "onda-1")
        #expect(card.runId == "wf_0a1b2c3d-4e5")
        #expect(card.agentCount == 4)
        #expect(card.toolUses == 80)
        #expect(card.durationMs == 600_000)
        #expect(document.items.count == 1)
    }

    @Test func lineWithThreeBlocksUpdatesTheCardsAndKeepsTheNotice() throws {
        let uuid = "notify-3"
        let text = [
            N.block(taskId: N.agentId, toolUseId: "toolu_a", summary: "Agent \"A\" finished"),
            N.block(taskId: "wabc12345", toolUseId: "toolu_w", summary: "Dynamic workflow \"W\" completed"),
            N.block(taskId: "bk7q2m9xa", summary: "Background command \"npm test\" completed (exit code 0)"),
        ].joined(separator: "\n")
        let document = L.document(N.agentLaunch(toolUseId: "toolu_a") + N.workflowLaunch(toolUseId: "toolu_w") + [N.userNotification(text, uuid: uuid)])
        #expect(N.subagents(document).first?.status == .completed)
        #expect(N.workflows(document).first?.status == .completed)
        #expect(document.items.last == ChatItem(
            id: uuid,
            at: try #require(ProtocolDate.date(from: "2026-09-25T15:00:00.000Z")),
            kind: .notice(text: "Background command \"npm test\" completed (exit code 0)")
        ))
    }

    @Test func noticesOnTheSameLineUseTheBlockIndex() {
        let text = [
            N.block(taskId: N.agentId, summary: "Agent \"A\" finished"),
            N.block(taskId: "bk7q2m9xa", summary: "primeiro"),
            N.block(taskId: nil, summary: "segundo"),
        ].joined(separator: "\n")
        let document = L.document([N.userNotification(text, uuid: "linha")])
        #expect(document.items.map(\.id) == ["linha#1", "linha#2"])
        #expect(document.items.map(\.kind) == [.notice(text: "primeiro"), .notice(text: "segundo")])
    }

    @Test func notificationForAnUnknownCardProducesNothing() {
        let text = N.block(taskId: N.agentId, toolUseId: "toolu_outro", summary: "Agent \"A\" finished")
        let workflow = N.block(taskId: "wzzzzzzzz", summary: "Dynamic workflow \"W\" completed")
        let document = L.document([N.userNotification(text), N.attachmentNotification(workflow)])
        #expect(document.items.isEmpty)
        #expect(document.changes.isEmpty)
    }

    @Test func notificationIsDetectedBeforeTheMetaRuleAndOnlyByItsFields() throws {
        let text = N.block(taskId: N.agentId, toolUseId: "toolu_a", summary: "Agent \"A\" finished")
        let lines = N.agentLaunch(toolUseId: "toolu_a") + [
            L.json(["type": "queue-operation", "operation": "enqueue", "timestamp": "2026-09-25T15:00:02.000Z", "content": text]),
            L.json([
                "type": "attachment", "uuid": "snap", "timestamp": "2026-09-25T15:00:02.000Z",
                "attachment": ["type": "prompt_snapshot", "prompt": text],
            ]),
            L.json([
                "type": "attachment", "uuid": "deferred", "timestamp": "2026-09-25T15:00:02.000Z",
                "attachment": ["type": "deferred_tools_record", "content": "Use <task-notification> blocks."],
            ]),
            L.user(text),
        ]
        let document = L.document(lines)
        #expect(document.items.count == 2)
        #expect(N.subagents(document).first?.status == .running)
        #expect(document.items.last?.kind == .userPrompt(text: text, imageCount: 0))
        #expect(document.statistics.unknown.isEmpty)

        let meta = L.document(N.agentLaunch(toolUseId: "toolu_a") + [N.userNotification("[SYSTEM NOTIFICATION - NOT USER INPUT]\n" + text, extra: ["isMeta": true])])
        #expect(N.subagents(meta).first?.status == .completed)
        #expect(meta.items.count == 1)
    }

    @Test func peerLinesAreIgnoredWithOrWithoutMeta() {
        let document = L.document([
            L.user("Another Claude session sent a message: relatório", extra: ["origin": ["kind": "peer", "handback": true]]),
            L.user("Another Claude session sent a message: relatório", extra: ["origin": ["kind": "peer"], "isMeta": true]),
        ])
        #expect(document.items.isEmpty)
    }
}
