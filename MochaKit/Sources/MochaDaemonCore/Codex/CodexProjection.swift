import Foundation
import MochaProtocol
import MochaTranscript

struct CodexThreadPage: Sendable, Equatable {
    let threadId: String
    let cwd: String
    let title: String
    let status: AgentStatus
    let activeTurnId: String?
    let items: [ChatItem]
    let before: String?
    let cards: [String: ChatItem]
    let outcomes: [String: CodexSubagentOutcome]
}

struct CodexItemEntry: Sendable, Equatable {
    let turnId: String?
    let item: OrderedJSON
    let startedAt: Date?
    let isCompleted: Bool

    var id: String? { item["id"]?.stringValue }
}

enum CodexProjection {
    static let summaryLimit = 120
    static let inputLimit = 4_000
    static let resultLimit = 2_000
    static let contextReserve = 12_000
    static let shellToolName = "Shell"
    static let editToolName = "Edit"
    static let interruptedNotice = "Interrompido"
    static let failedNotice = "O turno falhou."
    static let compactedNotice = "Contexto compactado"
    static let imageOnlyPreview = "[imagem]"

    static func status(_ value: OrderedJSON?) -> AgentStatus {
        switch value?["type"]?.stringValue {
        case "idle": .idle
        case "active": .working
        case "systemError": .unknown
        default: .unknown
        }
    }

    static func entries(_ listed: OrderedJSON) -> [CodexItemEntry] {
        (listed["data"]?.arrayValue ?? []).compactMap { entry in
            guard let item = entry["item"], item["id"]?.stringValue != nil else { return nil }
            return CodexItemEntry(
                turnId: entry["turnId"]?.stringValue,
                item: item,
                startedAt: date(milliseconds: entry["startedAtMs"]),
                isCompleted: entry["completedAtMs"]?.doubleValue != nil
            )
        }
    }

    static func page(
        thread: OrderedJSON,
        listed: OrderedJSON,
        turns: [String: CodexTurn],
        newerTurnId: String?,
        cards knownCards: [String: ChatItem] = [:],
        outcomes knownOutcomes: [String: CodexSubagentOutcome] = [:]
    ) -> CodexThreadPage? {
        guard let threadId = thread["id"]?.stringValue, let cwd = thread["cwd"]?.stringValue else { return nil }
        let chronological = Array(entries(listed).reversed())
        let fallback = date(seconds: thread["updatedAt"]) ?? Date(timeIntervalSince1970: 0)
        var outcomes = knownOutcomes
        for entry in chronological {
            if let found = subagentOutcome(entry.item), outcomes[found.child] == nil {
                outcomes[found.child] = CodexSubagentOutcome(status: found.status, at: entry.startedAt ?? fallback)
            }
        }
        var items: [ChatItem] = []
        var cards = knownCards
        var closedTurns: Set<String> = []
        for (index, entry) in chronological.enumerated() {
            let at = entry.startedAt ?? fallback
            if let card = subagentCard(entry.item, at: at, status: nil) {
                let child = subagentChild(card)
                let projected = child.flatMap { outcomes[$0] }.map { withOutcome(card, $0) } ?? card
                if let child { cards[child] = projected }
                items.append(projected)
            } else if let item = item(entry.item, at: at, isCompleted: entry.isCompleted, cwd: cwd) {
                items.append(item)
            }
            guard let turnId = entry.turnId, !closedTurns.contains(turnId) else { continue }
            let isLast = index == chronological.count - 1
            let endsHere = isLast ? newerTurnId != turnId : chronological[index + 1].turnId != turnId
            guard endsHere, let turn = turns[turnId], let closing = closingItem(turn, after: items.last?.at, fallback: at) else { continue }
            closedTurns.insert(turnId)
            items.append(closing)
        }
        let activeTurnId = turns.values.first { $0.status == .inProgress }?.id
        return CodexThreadPage(
            threadId: threadId,
            cwd: cwd,
            title: title(of: thread) ?? "Codex",
            status: status(thread["status"]),
            activeTurnId: activeTurnId,
            items: items,
            before: listed["nextCursor"]?.stringValue,
            cards: cards,
            outcomes: outcomes
        )
    }

    static func title(of thread: OrderedJSON) -> String? {
        nonEmpty(thread["name"]?.stringValue) ?? nonEmpty(thread["preview"]?.stringValue)
    }

    static func item(_ raw: OrderedJSON, at: Date, isCompleted: Bool, cwd: String?) -> ChatItem? {
        guard let id = raw["id"]?.stringValue, let type = raw["type"]?.stringValue else { return nil }
        switch type {
        case "userMessage":
            let content = raw["content"]?.arrayValue ?? []
            let text = content.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            let images = content.filter { ["image", "localImage"].contains($0["type"]?.stringValue ?? "") }
            let paths = images.filter { $0["type"]?.stringValue == "localImage" }.compactMap { $0["path"]?.stringValue }
            return ChatItem(id: id, at: at, kind: .userPrompt(text: text, imageCount: images.count), imagePaths: paths)
        case "agentMessage":
            guard let text = nonEmpty(raw["text"]?.stringValue) else { return nil }
            return ChatItem(id: id, at: at, kind: .assistantText(markdown: text))
        case "plan":
            guard let text = nonEmpty(raw["text"]?.stringValue) else { return nil }
            return ChatItem(id: id, at: at, kind: .plan(markdown: text))
        case "reasoning":
            let summary = (raw["summary"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: "\n")
            return ChatItem(id: id, at: at, kind: .thinking(text: nonEmpty(summary)))
        case "contextCompaction":
            return ChatItem(id: id, at: at, kind: .notice(text: compactedNotice))
        case "collabAgentToolCall", "subAgentActivity":
            return nil
        case "imageView":
            guard let path = raw["path"]?.stringValue else { return nil }
            let call = ToolCall(
                toolUseId: id,
                name: "Read",
                summary: limited(relative(path, to: cwd), summaryLimit),
                inputJSON: object(["file_path": .string(path)]),
                status: isCompleted ? .succeeded : .running
            )
            return ChatItem(id: id, at: at, kind: .toolCall(call), imagePaths: [path])
        default:
            guard let call = toolCall(raw, id: id, type: type, isCompleted: isCompleted, cwd: cwd) else {
                return ChatItem(id: id, at: at, kind: .unsupported(type: type))
            }
            return ChatItem(id: id, at: at, kind: .toolCall(call))
        }
    }

    static func subagentCard(_ raw: OrderedJSON, at: Date, status: SubagentStatus?) -> ChatItem? {
        guard raw["type"]?.stringValue == "subAgentActivity", raw["kind"]?.stringValue == "started",
              let id = raw["id"]?.stringValue, let child = raw["agentThreadId"]?.stringValue else { return nil }
        let name = agentName(path: raw["agentPath"]?.stringValue) ?? "subagente"
        return ChatItem(id: id, at: at, kind: .subagent(SubagentCall(
            toolUseId: id,
            agentId: child,
            agentType: name,
            description: name,
            status: status ?? .running,
            startedAt: at
        )))
    }

    static func subagentOutcome(_ raw: OrderedJSON) -> (child: String, status: SubagentStatus)? {
        guard raw["type"]?.stringValue == "subAgentActivity", let child = raw["agentThreadId"]?.stringValue else { return nil }
        switch raw["kind"]?.stringValue {
        case "completed": return (child, .completed)
        case "interrupted": return (child, .stopped)
        default: return nil
        }
    }

    static func subagentChild(_ card: ChatItem) -> String? {
        guard case .subagent(let call) = card.kind else { return nil }
        return call.agentId
    }

    static func withOutcome(_ card: ChatItem, _ outcome: CodexSubagentOutcome) -> ChatItem {
        guard case .subagent(var call) = card.kind else { return card }
        call.status = outcome.status
        if let startedAt = call.startedAt {
            call.durationMs = max(0, Int((outcome.at.timeIntervalSince(startedAt) * 1000).rounded()))
        }
        var updated = card
        updated.kind = .subagent(call)
        return updated
    }

    static func agentName(path: String?) -> String? {
        guard let path else { return nil }
        return path.split(separator: "/").last.map(String.init).flatMap(nonEmpty)
    }

    static func closingItem(_ turn: CodexTurn, after last: Date? = nil, fallback: Date) -> ChatItem? {
        let id = "\(turn.id)#end"
        let completedAt = turn.completedAt ?? fallback
        let at = last.map { max($0, completedAt) } ?? completedAt
        switch turn.status {
        case .completed:
            return turn.durationMs.map { ChatItem(id: id, at: at, kind: .turnFooter(durationMs: $0)) }
        case .interrupted:
            return ChatItem(id: id, at: at, kind: .notice(text: interruptedNotice))
        case .failed:
            return ChatItem(id: id, at: at, kind: .notice(text: nonEmpty(turn.errorMessage) ?? failedNotice))
        case .inProgress:
            return nil
        }
    }

    static func preview(of item: ChatItem) -> MessagePreview? {
        switch item.kind {
        case .userPrompt(let text, let imageCount):
            let preview = PlainText.preview(fromMarkdown: text)
            if preview.isEmpty {
                return imageCount > 0 ? MessagePreview(author: .user, text: imageOnlyPreview) : nil
            }
            return MessagePreview(author: .user, text: preview)
        case .assistantText(let markdown):
            let preview = PlainText.preview(fromMarkdown: markdown)
            return preview.isEmpty ? nil : MessagePreview(author: .assistant, text: preview)
        default:
            return nil
        }
    }

    static func activity(of item: ChatItem) -> ToolActivity? {
        guard case .toolCall(let call) = item.kind else { return nil }
        return ToolActivity(toolName: call.name, summary: call.summary, status: call.status)
    }

    static func contextLeftPercent(lastTokens: Int, window: Int) -> Int? {
        let usable = window - contextReserve
        guard usable > 0 else { return nil }
        let used = max(0, lastTokens - contextReserve)
        let left = Double(usable - used) * 100 / Double(usable)
        return Int(min(100, max(0, left.rounded())))
    }

    static func settings(_ raw: OrderedJSON?, fallback: CodexThreadSettings = CodexThreadSettings()) -> CodexThreadSettings {
        guard let raw else { return fallback }
        let effort = raw["effort"] ?? raw["reasoningEffort"]
        return CodexThreadSettings(
            model: raw["model"].map(\.stringValue) ?? fallback.model,
            effort: effort.map(\.stringValue) ?? fallback.effort,
            mode: raw["collaborationMode"]?["mode"]?.stringValue ?? fallback.mode
        )
    }

    static func usage(_ raw: OrderedJSON, account: CodexAccount? = nil, at: Date = Date()) -> UsageSnapshot? {
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
        return UsageSnapshot(provider: .codex, plan: account?.plan, account: account?.email, windows: windows, fetchedAt: at)
    }

    static func account(_ raw: OrderedJSON) -> CodexAccount {
        let account = raw["account"] ?? .null
        return CodexAccount(
            plan: account["planType"]?.stringValue.flatMap(planName),
            email: account["email"]?.stringValue.flatMap(ClaudeAccount.maskedEmail)
        )
    }

    static func planName(_ planType: String) -> String? {
        let names = [
            "free": "Free", "go": "Go", "plus": "Plus", "pro": "Pro", "prolite": "Pro Lite", "promax": "Pro Max",
            "team": "Team", "business": "Business", "enterprise": "Enterprise", "edu": "Edu",
        ]
        if let name = names[planType] { return name }
        guard planType != "unknown", !planType.isEmpty else { return nil }
        return planType.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func date(milliseconds value: OrderedJSON?) -> Date? {
        value?.doubleValue.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    static func date(seconds value: OrderedJSON?) -> Date? {
        value?.doubleValue.map { Date(timeIntervalSince1970: $0) }
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.allSatisfy(\.isWhitespace) else { return nil }
        return text
    }

    private static func toolCall(_ raw: OrderedJSON, id: String, type: String, isCompleted: Bool, cwd: String?) -> ToolCall? {
        switch type {
        case "commandExecution":
            let actions = (raw["commandActions"]?.arrayValue ?? []).compactMap { $0["command"]?.stringValue }.filter { !$0.isEmpty }
            let command = actions.isEmpty ? raw["command"]?.stringValue ?? "" : actions.joined(separator: "\n")
            let status: ToolStatus = switch raw["status"]?.stringValue {
            case "inProgress": .running
            case "completed": (raw["exitCode"]?.intValue ?? 0) == 0 ? .succeeded : .failed
            case "failed", "declined": .failed
            default: isCompleted ? .succeeded : .running
            }
            return ToolCall(
                toolUseId: id,
                name: shellToolName,
                summary: limited(firstLine(actions.first ?? command), summaryLimit),
                inputJSON: object(["command": .string(command)]),
                status: status,
                resultPreview: raw["aggregatedOutput"]?.stringValue.flatMap(nonEmpty).map { limited($0, resultLimit) }
            )
        case "fileChange":
            let changes = raw["changes"]?.arrayValue ?? []
            let paths = changes.compactMap { $0["path"]?.stringValue }
            var input: [String: OrderedJSON] = [:]
            if let first = paths.first { input["file_path"] = .string(first) }
            if paths.count > 1 { input["paths"] = .array(paths.map(OrderedJSON.string)) }
            let diff = changes.compactMap { $0["diff"]?.stringValue }.joined(separator: "\n")
            return ToolCall(
                toolUseId: id,
                name: editToolName,
                summary: limited(paths.map { relative($0, to: cwd) }.joined(separator: ", "), summaryLimit),
                inputJSON: object(input),
                status: patchStatus(raw["status"]?.stringValue, isCompleted: isCompleted),
                resultPreview: nonEmpty(diff).map { limited($0, resultLimit) }
            )
        case "webSearch":
            let query = nonEmpty(raw["query"]?.stringValue) ?? nonEmpty(raw["action"]?["query"]?.stringValue) ?? nonEmpty(raw["action"]?["url"]?.stringValue) ?? ""
            return ToolCall(
                toolUseId: id,
                name: "WebSearch",
                summary: limited(firstLine(query), summaryLimit),
                inputJSON: object(["query": .string(query)]),
                status: isCompleted ? .succeeded : .running
            )
        case "mcpToolCall":
            let server = raw["server"]?.stringValue ?? "mcp"
            let tool = raw["tool"]?.stringValue ?? "tool"
            let arguments = raw["arguments"] ?? .object([])
            let result = nonEmpty(raw["error"]?["message"]?.stringValue) ?? contentText(raw["result"]?["content"])
            return ToolCall(
                toolUseId: id,
                name: "mcp__\(server)__\(tool)",
                summary: limited(firstLine(firstString(arguments) ?? ""), summaryLimit),
                inputJSON: limited(arguments.compactSerialized(), inputLimit),
                status: callStatus(raw["status"]?.stringValue, isCompleted: isCompleted),
                resultPreview: result.map { limited($0, resultLimit) }
            )
        case "dynamicToolCall":
            let arguments = raw["arguments"] ?? .object([])
            let failed = raw["success"]?.boolValue == false
            return ToolCall(
                toolUseId: id,
                name: raw["tool"]?.stringValue ?? "Ferramenta",
                summary: limited(firstLine(firstString(arguments) ?? ""), summaryLimit),
                inputJSON: limited(arguments.compactSerialized(), inputLimit),
                status: failed ? .failed : callStatus(raw["status"]?.stringValue, isCompleted: isCompleted),
                resultPreview: contentText(raw["contentItems"]).map { limited($0, resultLimit) }
            )
        case "imageGeneration":
            return ToolCall(
                toolUseId: id,
                name: "imageGeneration",
                summary: limited(firstLine(raw["revisedPrompt"]?.stringValue ?? ""), summaryLimit),
                inputJSON: "{}",
                status: callStatus(raw["status"]?.stringValue, isCompleted: isCompleted)
            )
        default:
            return nil
        }
    }

    private static func patchStatus(_ value: String?, isCompleted: Bool) -> ToolStatus {
        switch value {
        case "inProgress": .running
        case "completed": .succeeded
        case "failed", "declined": .failed
        default: isCompleted ? .succeeded : .running
        }
    }

    private static func callStatus(_ value: String?, isCompleted: Bool) -> ToolStatus {
        switch value {
        case "inProgress": .running
        case "completed": .succeeded
        case "failed": .failed
        default: isCompleted ? .succeeded : .running
        }
    }

    private static func contentText(_ value: OrderedJSON?) -> String? {
        guard let content = value?.arrayValue else { return nil }
        let texts = content.compactMap { part -> String? in
            if let text = part["text"]?.stringValue { return text }
            return part["type"]?.stringValue == "image" || part["type"]?.stringValue == "inputImage" ? "[imagem]" : nil
        }
        return nonEmpty(texts.joined(separator: "\n"))
    }

    private static func firstString(_ value: OrderedJSON) -> String? {
        for member in value.members ?? [] {
            if let text = nonEmpty(member.value.stringValue) { return text }
        }
        return nil
    }

    private static func firstLine(_ text: String) -> String {
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func limited(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) : text
    }

    private static func object(_ values: [String: OrderedJSON]) -> String {
        OrderedJSON.object(values.sorted { $0.key < $1.key }.map { OrderedJSON.Member($0.key, $0.value) }).compactSerialized()
    }

    static func relative(_ path: String, to cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return path }
        let prefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return path }
        return String(path.dropFirst(prefix.count))
    }
}
