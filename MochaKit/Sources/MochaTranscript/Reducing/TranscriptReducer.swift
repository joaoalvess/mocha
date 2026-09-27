import Foundation
import MochaProtocol

struct TranscriptReducer {
    private struct LastSlashCommand {
        var item: ChatItem
        var promptId: String?

        var name: String? {
            if case .slashCommand(let name, _, _) = item.kind { return name }
            return nil
        }
    }

    private(set) var statistics = TranscriptStatistics()
    private var runningToolCalls: [String: ChatItem] = [:]
    private var subagentCards: [String: ChatItem] = [:]
    private var subagentToolUseIds: [String: String] = [:]
    private var workflowCards: [String: ChatItem] = [:]
    private var workflowToolUseIds: [String: String] = [:]
    private var lastSlashCommand: LastSlashCommand?

    mutating func apply(_ line: ParsedLine) -> [TranscriptChange] {
        var changes: [TranscriptChange] = []
        for effect in line.effects {
            switch effect {
            case .dropped:
                statistics.dropped += 1
            case .unknown(let name):
                statistics.unknown[name, default: 0] += 1
            case .title, .permissionMode, .modelAndBranch, .contextTokens, .turnStarted, .turnEnded:
                break
            case .item(let item):
                switch item.kind {
                case .toolCall(let call):
                    runningToolCalls[call.toolUseId] = item
                case .subagent(let call):
                    subagentCards[call.toolUseId] = item
                case .workflow(let call):
                    workflowCards[call.toolUseId] = item
                default:
                    break
                }
                changes.append(.append(item))
            case .slashCommand(let item, let promptId):
                if let promptId, let last = lastSlashCommand, last.promptId == promptId, last.name == Self.name(of: item) {
                    continue
                }
                lastSlashCommand = LastSlashCommand(item: item, promptId: promptId)
                changes.append(.append(item))
            case .commandOutput(let output):
                guard !output.isEmpty, var last = lastSlashCommand,
                      case .slashCommand(let name, let args, let existing) = last.item.kind else {
                    continue
                }
                let combined = existing.map { "\($0)\n\(output)" } ?? output
                last.item.kind = .slashCommand(name: name, args: args, output: combined)
                lastSlashCommand = last
                changes.append(.update(last.item))
            case .toolResult(let outcome):
                if let item = applyToolResult(outcome) {
                    changes.append(.update(item))
                } else {
                    statistics.orphanResults += 1
                }
            case .taskNotification(let notification):
                if let item = applyNotification(notification) {
                    changes.append(.update(item))
                }
            }
        }
        return changes
    }

    private mutating func applyToolResult(_ outcome: ToolResultOutcome) -> ChatItem? {
        if var item = runningToolCalls.removeValue(forKey: outcome.toolUseId), case .toolCall(var call) = item.kind {
            call.status = outcome.isError ? .failed : .succeeded
            let answers = call.name == "AskUserQuestion" ? outcome.answersPreview : nil
            call.resultPreview = answers ?? outcome.preview
            item.kind = .toolCall(call)
            return item
        }
        if var item = subagentCards[outcome.toolUseId], case .subagent(var call) = item.kind {
            let result = outcome.toolUseResult
            if outcome.isError {
                call.status = .failed
                call.failureReason = outcome.preview
            } else if let result, result.isAsyncLaunch {
                call.agentId = result.agentId ?? call.agentId
            } else if let result, let toolUses = result.totalToolUseCount, let durationMs = result.totalDurationMs {
                call.status = .completed
                call.agentId = result.agentId ?? call.agentId
                call.toolUses = toolUses
                call.durationMs = durationMs
            }
            if let agentId = call.agentId {
                subagentToolUseIds[agentId] = call.toolUseId
            }
            item.kind = .subagent(call)
            subagentCards[call.toolUseId] = item
            return item
        }
        if var item = workflowCards[outcome.toolUseId], case .workflow(var call) = item.kind {
            if outcome.isError {
                call.status = .failed
            } else if let result = outcome.toolUseResult, result.isAsyncLaunch {
                call.runId = result.runId ?? call.runId
                if let name = result.workflowName, !name.isEmpty {
                    call.name = name
                }
                if let taskId = result.taskId {
                    workflowToolUseIds[taskId] = call.toolUseId
                }
            }
            item.kind = .workflow(call)
            workflowCards[call.toolUseId] = item
            return item
        }
        return nil
    }

    private mutating func applyNotification(_ notification: TaskNotification) -> ChatItem? {
        switch notification.kind {
        case .agent:
            guard let toolUseId = cardId(for: notification, cards: subagentCards, byTaskId: subagentToolUseIds),
                  var item = subagentCards[toolUseId],
                  case .subagent(var call) = item.kind else {
                return nil
            }
            if call.agentId == nil, let taskId = notification.taskId {
                call.agentId = taskId
                subagentToolUseIds[taskId] = toolUseId
            }
            if let status = notification.subagentStatus {
                call.status = status
                if status != .running {
                    call.toolUses = notification.toolUses ?? call.toolUses
                    call.durationMs = notification.durationMs ?? call.durationMs
                }
                call.failureReason = status == .failed ? notification.failureReason : nil
            }
            item.kind = .subagent(call)
            subagentCards[toolUseId] = item
            return item
        case .workflow:
            guard let toolUseId = cardId(for: notification, cards: workflowCards, byTaskId: workflowToolUseIds),
                  var item = workflowCards[toolUseId],
                  case .workflow(var call) = item.kind else {
                return nil
            }
            if let status = notification.workflowStatus {
                call.status = status
                call.agentCount = notification.agentCount ?? call.agentCount
                call.toolUses = notification.toolUses ?? call.toolUses
                call.durationMs = notification.durationMs ?? call.durationMs
            }
            item.kind = .workflow(call)
            workflowCards[toolUseId] = item
            return item
        case .other:
            return nil
        }
    }

    private func cardId(for notification: TaskNotification, cards: [String: ChatItem], byTaskId: [String: String]) -> String? {
        if let toolUseId = notification.toolUseId, cards[toolUseId] != nil {
            return toolUseId
        }
        return notification.taskId.flatMap { byTaskId[$0] }
    }

    private static func name(of item: ChatItem) -> String? {
        if case .slashCommand(let name, _, _) = item.kind { return name }
        return nil
    }
}
