import Foundation
import MochaProtocol

struct CodexThreadPage: Sendable {
    let threadId: String
    let cwd: String
    let title: String
    let status: AgentStatus
    let activeTurnId: String?
    let items: [ChatItem]
    let before: String?
}

enum CodexProjection {
    static func status(_ value: OrderedJSON?) -> AgentStatus {
        switch value?["type"]?.stringValue {
        case "idle": .idle
        case "active": .working
        case "systemError": .unknown
        default: .unknown
        }
    }

    static func page(thread: OrderedJSON, turns: OrderedJSON) -> CodexThreadPage? {
        guard let threadId = thread["id"]?.stringValue, let cwd = thread["cwd"]?.stringValue else { return nil }
        let rawTurns = turns["data"]?.arrayValue ?? []
        let flattened = rawTurns.reversed().flatMap { turn -> [ChatItem] in
            let at = Date(timeIntervalSince1970: TimeInterval(turn["startedAt"]?.doubleValue ?? thread["updatedAt"]?.doubleValue ?? 0))
            return (turn["items"]?.arrayValue ?? []).compactMap { item($0, at: at) }
        }
        let activeTurnId = rawTurns.first { $0["status"]?.stringValue == "inProgress" }?["id"]?.stringValue
        return CodexThreadPage(
            threadId: threadId,
            cwd: cwd,
            title: thread["name"]?.stringValue ?? thread["preview"]?.stringValue ?? "Codex",
            status: status(thread["status"]),
            activeTurnId: activeTurnId,
            items: flattened,
            before: turns["nextCursor"]?.stringValue
        )
    }

    static func item(_ raw: OrderedJSON, at: Date) -> ChatItem? {
        guard let id = raw["id"]?.stringValue, let type = raw["type"]?.stringValue else { return nil }
        let kind: ChatItemKind
        switch type {
        case "userMessage":
            let content = raw["content"]?.arrayValue ?? []
            let text = content.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            let images = content.filter { ["image", "localImage"].contains($0["type"]?.stringValue ?? "") }.count
            kind = .userPrompt(text: text, imageCount: images)
        case "agentMessage":
            kind = .assistantText(markdown: raw["text"]?.stringValue ?? "")
        case "plan":
            kind = .plan(markdown: raw["text"]?.stringValue ?? "")
        case "reasoning":
            let summary = raw["summary"]?.arrayValue?.compactMap(\.stringValue).joined(separator: "\n")
            kind = .thinking(text: summary)
        case "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch", "imageView", "imageGeneration":
            let name: String
            let detail: String
            switch type {
            case "commandExecution":
                name = "Comando"
                detail = raw["command"]?.stringValue ?? ""
            case "fileChange":
                name = "Arquivos"
                detail = "Alteração de arquivos"
            case "mcpToolCall":
                name = raw["tool"]?.stringValue ?? "MCP"
                detail = raw["server"]?.stringValue ?? ""
            case "dynamicToolCall":
                name = raw["tool"]?.stringValue ?? "Ferramenta"
                detail = raw["namespace"]?.stringValue ?? ""
            default:
                name = type
                detail = type
            }
            let rawStatus = raw["status"]?.stringValue ?? ""
            let status: ToolStatus = switch rawStatus {
            case "completed": .succeeded
            case "failed", "declined": .failed
            default: .running
            }
            kind = .toolCall(ToolCall(
                toolUseId: id,
                name: name,
                summary: detail,
                inputJSON: raw["arguments"]?.compactSerialized() ?? "{}",
                status: status,
                resultPreview: raw["aggregatedOutput"]?.stringValue
            ))
        case "collabAgentToolCall":
            let status: SubagentStatus = switch raw["status"]?.stringValue {
            case "completed": .completed
            case "failed": .failed
            default: .running
            }
            kind = .subagent(SubagentCall(
                toolUseId: id,
                agentId: raw["receiverThreadIds"]?.arrayValue?.first?.stringValue,
                agentType: "Codex",
                description: raw["prompt"]?.stringValue ?? raw["tool"]?.stringValue ?? "Subagente",
                status: status
            ))
        case "subAgentActivity":
            kind = .notice(text: "Atividade do subagente")
        default:
            kind = .unsupported(type: type)
        }
        return ChatItem(id: id, at: at, kind: kind)
    }

    static func usage(_ raw: OrderedJSON, at: Date = Date()) -> UsageSnapshot? {
        let limits = raw["rateLimitsByLimitId"]?.members?.first { $0.value["primary"] != nil }?.value ?? raw["rateLimits"] ?? raw
        let values = [limits["primary"], limits["secondary"]].compactMap { $0 }
        let windows = values.compactMap { value -> UsageWindow? in
            guard let used = value["usedPercent"]?.doubleValue else { return nil }
            let duration = value["windowDurationMins"]?.intValue
            let kind: UsageWindowKind = switch duration {
            case 300: .fiveHour
            case 10080: .weekly
            default: .unknown
            }
            let reset = value["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }
            return UsageWindow(kind: kind, usedPercent: used, resetsAt: reset, windowDurationMins: duration)
        }
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(provider: .codex, windows: windows, fetchedAt: at)
    }
}
