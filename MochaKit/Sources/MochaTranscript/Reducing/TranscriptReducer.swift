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
                if case .toolCall(let call) = item.kind {
                    runningToolCalls[call.toolUseId] = item
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
                guard var item = runningToolCalls.removeValue(forKey: outcome.toolUseId),
                      case .toolCall(var call) = item.kind else {
                    statistics.orphanResults += 1
                    continue
                }
                call.status = outcome.isError ? .failed : .succeeded
                let answers = call.name == "AskUserQuestion" ? outcome.answersPreview : nil
                call.resultPreview = answers ?? outcome.preview
                item.kind = .toolCall(call)
                changes.append(.update(item))
            }
        }
        return changes
    }

    private static func name(of item: ChatItem) -> String? {
        if case .slashCommand(let name, _, _) = item.kind { return name }
        return nil
    }
}
