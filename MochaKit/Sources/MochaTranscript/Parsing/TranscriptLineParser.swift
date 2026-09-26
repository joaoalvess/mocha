import Foundation
import MochaProtocol

enum TranscriptLineParser {
    static let interruptionNotice = "Interrompido pelo usuário"
    static let compactNotice = "Conversa compactada"

    private static let ignoredTypes: Set<String> = [
        "mode", "atis-latch", "last-prompt", "agent-name", "queue-operation", "file-history-snapshot",
        "file-history-delta", "worktree-state", "relocated", "cost-state", "pr-link", "frame-link",
        "fork-context-ref", "bridge-session", "continued-in",
    ]
    private static let noticeSystemSubtypes: Set<String> = ["informational", "model_consent_fallback", "api_error"]
    private static let ignoredSystemSubtypes: Set<String> = ["stop_hook_summary", "bridge_status", "agents_killed"]
    private static let interruptionMarkers: Set<String> = [
        "[Request interrupted by user]",
        "[Request interrupted by user for tool use]",
    ]
    private static let syntheticModel = "<synthetic>"
    private static let detachedBranch = "HEAD"

    static func parse(_ bytes: [UInt8], offset: UInt64) -> ParsedLine {
        bytes.withUnsafeBytes { parse($0, offset: offset) }
    }

    static func parse(_ bytes: UnsafeRawBufferPointer, offset: UInt64) -> ParsedLine {
        guard bytes.contains(where: { !isJSONWhitespace($0) }) else { return .empty }
        guard let root = try? JSONParser.parse(bytes).objectValue,
              let type = root["type"]?.stringValue else {
            return .dropped
        }
        let line = Line(object: root, offset: offset)
        let version = root["version"]?.stringValue
        guard !root["isSidechain"].isTrue else { return ParsedLine(version: version, effects: []) }
        return ParsedLine(version: version, effects: effects(type: type, line: line))
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func effects(type: String, line: Line) -> [LineEffect] {
        switch type {
        case "ai-title":
            return line["aiTitle"]?.stringValue.map { [.title($0)] } ?? []
        case "permission-mode":
            return line["permissionMode"]?.stringValue.map { [.permissionMode($0)] } ?? []
        case "attachment":
            return attachmentEffects(line)
        case "user":
            return userEffects(line)
        case "assistant":
            return assistantEffects(line)
        case "system":
            return systemEffects(line)
        default:
            return ignoredTypes.contains(type) ? [] : [.unknown("type:\(type)")]
        }
    }

    private static func attachmentEffects(_ line: Line) -> [LineEffect] {
        guard let attachment = line["attachment"], attachment["type"]?.stringValue == "queued_command" else { return [] }
        switch attachment["commandMode"]?.stringValue {
        case "prompt":
            let originKind = attachment["origin"]?["kind"]?.stringValue ?? line["origin"]?["kind"]?.stringValue
            guard originKind == nil || originKind == "human",
                  !attachment["isMeta"].isTrue,
                  !line["isMeta"].isTrue else {
                return []
            }
            switch attachment["prompt"] {
            case .string(let text):
                return [.item(line.item(.userPrompt(text: text, imageCount: 0)))]
            case .array(let blocks):
                return promptEffects(blocks: blocks, line: line)
            default:
                return []
            }
        case "task-notification":
            let text = attachment["prompt"].map(plainText) ?? ""
            return [.item(line.item(.notice(text: CommandMarkup.taskNotificationSummary(in: text))))]
        default:
            return []
        }
    }

    private static func userEffects(_ line: Line) -> [LineEffect] {
        guard !line["isMeta"].isTrue, !line["isCompactSummary"].isTrue else { return [] }
        switch line["message"]?["content"] {
        case .string(let text):
            return userTextEffects(text, line: line)
        case .array(let blocks):
            return userBlockEffects(blocks, line: line)
        default:
            return [.dropped]
        }
    }

    private static func userTextEffects(_ text: String, line: Line) -> [LineEffect] {
        let head = text.drop(while: \.isWhitespace)
        let promptId = line["promptId"]?.stringValue
        if let command = CommandMarkup.slashCommand(in: text) {
            return [.slashCommand(line.item(.slashCommand(name: command.name, args: command.args, output: nil)), promptId: promptId)]
        }
        if head.hasPrefix("<local-command-stdout>") || head.hasPrefix("<local-command-stderr>") {
            return [.commandOutput(CommandMarkup.localCommandOutput(in: text))]
        }
        if head.hasPrefix("<bash-input>") {
            let command = CommandMarkup.innerText(of: "bash-input", in: text)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return [.slashCommand(line.item(.slashCommand(name: "!", args: command, output: nil)), promptId: promptId)]
        }
        if head.hasPrefix("<bash-stdout>") || head.hasPrefix("<bash-stderr>") {
            return [.commandOutput(CommandMarkup.bashOutput(in: text))]
        }
        if line["origin"]?["kind"]?.stringValue == "task-notification" || head.hasPrefix("<task-notification>") {
            return [.item(line.item(.notice(text: CommandMarkup.taskNotificationSummary(in: text))))]
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/compact" || trimmed.hasPrefix("/compact ") {
            let args = trimmed.dropFirst("/compact".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return [.slashCommand(line.item(.slashCommand(name: "/compact", args: args, output: nil)), promptId: promptId)]
        }
        return [.item(line.item(.userPrompt(text: text, imageCount: 0)))]
    }

    private static func userBlockEffects(_ blocks: [JSONValue], line: Line) -> [LineEffect] {
        let results = blocks.filter { $0["type"]?.stringValue == "tool_result" }
        if !results.isEmpty {
            let answers = results.count == 1 ? ToolResultPreview.answersPreview(of: line["toolUseResult"]) : nil
            return results.compactMap { block in
                guard let toolUseId = block["tool_use_id"]?.stringValue else { return nil }
                return .toolResult(ToolResultOutcome(
                    toolUseId: toolUseId,
                    isError: block["is_error"].isTrue,
                    preview: ToolResultPreview.preview(of: block["content"]),
                    answersPreview: answers
                ))
            }
        }
        if blocks.count == 1,
           blocks[0]["type"]?.stringValue == "text",
           let text = blocks[0]["text"]?.stringValue,
           interruptionMarkers.contains(text) {
            return [.item(line.item(.notice(text: interruptionNotice)))]
        }
        return promptEffects(blocks: blocks, line: line)
    }

    private static func promptEffects(blocks: [JSONValue], line: Line) -> [LineEffect] {
        var texts: [String] = []
        var imageCount = 0
        var effects: [LineEffect] = []
        for block in blocks {
            switch block["type"]?.stringValue {
            case "text":
                texts.append(block["text"]?.stringValue ?? "")
            case "image":
                imageCount += 1
            case let other:
                effects.append(.unknown("block:\(other ?? "")"))
            }
        }
        guard !texts.isEmpty || imageCount > 0 else { return effects }
        return [.item(line.item(.userPrompt(text: texts.joined(separator: "\n"), imageCount: imageCount)))] + effects
    }

    private static func assistantEffects(_ line: Line) -> [LineEffect] {
        guard let message = line["message"] else { return [.dropped] }
        let blocks: [JSONValue]
        switch message["content"] {
        case .array(let values): blocks = values
        case .string(let text): blocks = [.object(JSONObject(members: [.init(key: "type", value: .string("text")), .init(key: "text", value: .string(text))]))]
        default: return [.dropped]
        }
        let model = message["model"]?.stringValue
        if line["isApiErrorMessage"].isTrue || model == syntheticModel {
            let text = blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined(separator: "\n")
            return [.item(line.item(.notice(text: text.trimmingCharacters(in: .whitespacesAndNewlines))))]
        }
        let branch = line["gitBranch"]?.stringValue.flatMap { $0 == detachedBranch || $0.isEmpty ? nil : $0 }
        var effects: [LineEffect] = [.modelAndBranch(model: model, branch: branch)]
        let usesBlockIndex = blocks.count > 1
        for (index, block) in blocks.enumerated() {
            let blockIndex = usesBlockIndex ? index : nil
            switch block["type"]?.stringValue {
            case "text":
                guard let text = block["text"]?.stringValue, !text.isBlank else { continue }
                effects.append(.item(line.item(.assistantText(markdown: text), blockIndex: blockIndex)))
            case "thinking":
                let text = block["thinking"]?.stringValue ?? ""
                effects.append(.item(line.item(.thinking(text: text.isEmpty ? nil : text), blockIndex: blockIndex)))
            case "redacted_thinking":
                effects.append(.item(line.item(.thinking(text: nil), blockIndex: blockIndex)))
            case "tool_use":
                effects.append(.item(line.item(.toolCall(toolCall(from: block, cwd: line["cwd"]?.stringValue)), blockIndex: blockIndex)))
            case let other:
                effects.append(.unknown("block:\(other ?? "")"))
            }
        }
        return effects
    }

    private static func toolCall(from block: JSONValue, cwd: String?) -> ToolCall {
        let name = block["name"]?.stringValue ?? ""
        let input = block["input"]
        return ToolCall(
            toolUseId: block["id"]?.stringValue ?? "",
            name: name,
            summary: ToolCallSummary.summary(toolName: name, input: input, cwd: cwd),
            inputJSON: (input ?? .object(JSONObject(members: []))).serialized().truncated(toCharacters: TextLimits.inputJSON),
            status: .running
        )
    }

    private static func systemEffects(_ line: Line) -> [LineEffect] {
        let subtype = line["subtype"]?.stringValue ?? ""
        let content = line["content"]?.stringValue
        switch subtype {
        case "turn_duration":
            guard let duration = line["durationMs"]?.intValue else { return [] }
            return [.item(line.item(.turnFooter(durationMs: duration)))]
        case "away_summary":
            guard let content else { return [] }
            return [.item(line.item(.recap(text: content)))]
        case "local_command":
            guard let content else { return [] }
            if let command = CommandMarkup.slashCommand(in: content) {
                let item = line.item(.slashCommand(name: command.name, args: command.args, output: nil))
                return [.slashCommand(item, promptId: line["promptId"]?.stringValue)]
            }
            if content.contains("<local-command-stdout>") || content.contains("<local-command-stderr>") {
                return [.commandOutput(CommandMarkup.localCommandOutput(in: content))]
            }
            return []
        case "compact_boundary":
            return [.item(line.item(.notice(text: compactNotice)))]
        case _ where noticeSystemSubtypes.contains(subtype):
            guard let content else { return [] }
            return [.item(line.item(.notice(text: content)))]
        case _ where ignoredSystemSubtypes.contains(subtype):
            return []
        default:
            return [.unknown("subtype:\(subtype)")]
        }
    }

    private static func plainText(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): text
        case .array(let blocks): blocks.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
        default: ""
        }
    }
}

private struct Line {
    let object: JSONObject
    let offset: UInt64

    subscript(key: String) -> JSONValue? {
        object[key]
    }

    func item(_ kind: ChatItemKind, blockIndex: Int? = nil) -> ChatItem {
        let base = object["uuid"]?.stringValue ?? "line@\(offset)"
        let id = blockIndex.map { "\(base)#\($0)" } ?? base
        return ChatItem(id: id, at: timestamp, kind: kind)
    }

    private var timestamp: Date {
        object["timestamp"]?.stringValue.flatMap(ProtocolDate.date(from:)) ?? Date(timeIntervalSince1970: 0)
    }
}

private extension Optional where Wrapped == JSONValue {
    var isTrue: Bool {
        self?.isTrue ?? false
    }
}
