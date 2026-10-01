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

    private static let forkDirectiveMarker = "Your directive: "
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

    static func parse(_ bytes: [UInt8], offset: UInt64, mode: LineMode = .main) -> ParsedLine {
        bytes.withUnsafeBytes { parse($0, offset: offset, mode: mode) }
    }

    static func parse(_ bytes: UnsafeRawBufferPointer, offset: UInt64, mode: LineMode = .main) -> ParsedLine {
        guard bytes.contains(where: { !isJSONWhitespace($0) }) else { return .empty }
        if case .forkPrelude(let toolUseId) = mode {
            return forkPreludeLine(bytes, offset: offset, toolUseId: toolUseId)
        }
        guard let root = try? JSONParser.parse(bytes).objectValue,
              let type = root["type"]?.stringValue else {
            return .dropped
        }
        let line = Line(object: root, offset: offset, isSubagent: mode == .subagent)
        let version = root["version"]?.stringValue
        guard line.isSubagent || !root["isSidechain"].isTrue else { return ParsedLine(version: version, effects: []) }
        return ParsedLine(version: version, timestamp: root["timestamp"]?.stringValue, effects: effects(type: type, line: line))
    }

    private static func forkPreludeLine(_ bytes: UnsafeRawBufferPointer, offset: UInt64, toolUseId: String) -> ParsedLine {
        guard contains(Array(toolUseId.utf8), in: bytes),
              let root = try? JSONParser.parse(bytes).objectValue,
              root["type"]?.stringValue == "user",
              let blocks = root["message"]?["content"]?.arrayValue,
              blocks.contains(where: { $0["type"]?.stringValue == "tool_result" && $0["tool_use_id"]?.stringValue == toolUseId }) else {
            return .empty
        }
        let texts = blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }
        let directive = texts.lazy.compactMap { text in
            text.range(of: forkDirectiveMarker).map { String(text[$0.upperBound...]) }
        }.first ?? texts.first ?? ""
        let line = Line(object: root, offset: offset, isSubagent: true)
        return ParsedLine(
            version: root["version"]?.stringValue,
            timestamp: root["timestamp"]?.stringValue,
            effects: [.item(line.item(.task(text: directive.trimmingCharacters(in: .whitespacesAndNewlines))))],
            crossesForkBoundary: true
        )
    }

    private static func contains(_ needle: [UInt8], in bytes: UnsafeRawBufferPointer) -> Bool {
        guard !needle.isEmpty, let base = bytes.baseAddress, bytes.count >= needle.count else { return false }
        return needle.withUnsafeBytes { pattern in
            guard let patternBase = pattern.baseAddress else { return false }
            return memmem(base, bytes.count, patternBase, pattern.count) != nil
        }
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
                return [.item(userPrompt(text, imageCount: 0, line: line))]
            case .array(let blocks):
                return promptEffects(blocks: blocks, line: line)
            default:
                return []
            }
        case "task-notification":
            return taskNotificationEffects(attachment["prompt"].map(plainText) ?? "", line: line)
        default:
            return []
        }
    }

    private static func taskNotificationEffects(_ text: String, line: Line) -> [LineEffect] {
        let notifications = TaskNotification.parse(text)
        guard !notifications.isEmpty else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [.item(line.item(.notice(text: trimmed)))]
        }
        let noticeCount = notifications.count(where: { $0.kind == .other })
        return notifications.enumerated().map { index, notification in
            guard notification.kind == .other else { return .taskNotification(notification) }
            let summary = notification.summary ?? CommandMarkup.taskNotificationSummary(in: text)
            return .item(line.item(.notice(text: summary), blockIndex: noticeCount > 1 ? index : nil))
        }
    }

    private static func userEffects(_ line: Line) -> [LineEffect] {
        let originKind = line["origin"]?["kind"]?.stringValue
        if originKind == "peer" { return [] }
        let content = line["message"]?["content"]
        if originKind == "task-notification", case .string(let text) = content {
            return taskNotificationEffects(text, line: line)
        }
        guard !line["isMeta"].isTrue, !line["isCompactSummary"].isTrue else { return [] }
        if line.isSubagent, line.isRoot, let content {
            return [.item(line.item(.task(text: plainText(content).trimmingCharacters(in: .whitespacesAndNewlines))))]
        }
        let effects: [LineEffect]
        switch content {
        case .string(let text):
            effects = userTextEffects(text, line: line)
        case .array(let blocks):
            effects = userBlockEffects(blocks, line: line)
        default:
            return [.dropped]
        }
        return effects.contains(where: \.isUserPrompt) ? effects + [.turnStarted] : effects
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/compact" || trimmed.hasPrefix("/compact ") {
            let args = trimmed.dropFirst("/compact".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return [.slashCommand(line.item(.slashCommand(name: "/compact", args: args, output: nil)), promptId: promptId)]
        }
        return [.item(userPrompt(text, imageCount: 0, line: line))]
    }

    private static func userBlockEffects(_ blocks: [JSONValue], line: Line) -> [LineEffect] {
        let results = blocks.filter { $0["type"]?.stringValue == "tool_result" }
        if !results.isEmpty {
            let answers = results.count == 1 ? ToolResultPreview.answersPreview(of: line["toolUseResult"]) : nil
            let toolUseResult = results.count == 1 ? toolUseResultSummary(of: line["toolUseResult"]) : nil
            return results.compactMap { block in
                guard let toolUseId = block["tool_use_id"]?.stringValue else { return nil }
                return .toolResult(ToolResultOutcome(
                    toolUseId: toolUseId,
                    isError: block["is_error"].isTrue,
                    preview: ToolResultPreview.preview(of: block["content"]),
                    answersPreview: answers,
                    toolUseResult: toolUseResult
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

    private static func toolUseResultSummary(of value: JSONValue?) -> ToolUseResultSummary? {
        guard let value, value.objectValue != nil else { return nil }
        return ToolUseResultSummary(
            status: value["status"]?.stringValue,
            agentId: value["agentId"]?.stringValue,
            totalToolUseCount: value["totalToolUseCount"]?.intValue,
            totalDurationMs: value["totalDurationMs"]?.intValue,
            runId: value["runId"]?.stringValue,
            taskId: value["taskId"]?.stringValue,
            workflowName: value["workflowName"]?.stringValue
        )
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
        return [.item(userPrompt(texts.joined(separator: "\n"), imageCount: imageCount, line: line))] + effects
    }

    private static func userPrompt(_ text: String, imageCount: Int, line: Line) -> ChatItem {
        let markers = ImageMarkers.extract(from: text)
        return line.item(.userPrompt(text: markers.text, imageCount: imageCount + markers.count), imagePaths: markers.paths)
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
        if let tokens = contextTokens(in: message["usage"]) {
            effects.append(.contextTokens(tokens))
        }
        let usesBlockIndex = blocks.count > 1
        for (index, block) in blocks.enumerated() {
            let blockIndex = usesBlockIndex ? index : nil
            switch block["type"]?.stringValue {
            case "text":
                guard let text = block["text"]?.stringValue, !text.isBlank else { continue }
                let imagePaths = ImageMentions.paths(in: text, cwd: line["cwd"]?.stringValue, home: home)
                effects.append(.item(line.item(.assistantText(markdown: text), blockIndex: blockIndex, imagePaths: imagePaths)))
            case "thinking":
                let text = block["thinking"]?.stringValue ?? ""
                effects.append(.item(line.item(.thinking(text: text.isEmpty ? nil : text), blockIndex: blockIndex)))
            case "redacted_thinking":
                effects.append(.item(line.item(.thinking(text: nil), blockIndex: blockIndex)))
            case "tool_use":
                effects.append(.item(line.item(toolUseKind(block, line: line), blockIndex: blockIndex, imagePaths: readImagePaths(block))))
            case let other:
                effects.append(.unknown("block:\(other ?? "")"))
            }
        }
        return effects
    }

    private static func contextTokens(in usage: JSONValue?) -> Int? {
        guard let usage = usage?.objectValue else { return nil }
        let counts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage[$0]?.intValue }
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    private static func toolUseKind(_ block: JSONValue, line: Line) -> ChatItemKind {
        let toolUseId = block["id"]?.stringValue ?? ""
        let input = block["input"]
        switch block["name"]?.stringValue {
        case "Agent", "Task":
            return .subagent(SubagentCall(
                toolUseId: toolUseId,
                agentType: SubagentType.displayName(for: input?["subagent_type"]?.stringValue),
                description: input?["description"]?.stringValue ?? "",
                status: .running
            ))
        case "Workflow":
            return .workflow(WorkflowCall(
                toolUseId: toolUseId,
                name: WorkflowName.name(script: input?["script"]?.stringValue, scriptPath: input?["scriptPath"]?.stringValue),
                status: .running,
                startedAt: line.date
            ))
        default:
            return .toolCall(toolCall(from: block, cwd: line["cwd"]?.stringValue))
        }
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

    private static func readImagePaths(_ block: JSONValue) -> [String] {
        guard block["name"]?.stringValue == "Read",
              let path = block["input"]?["file_path"]?.stringValue,
              path.hasPrefix("/"),
              ImageFileExtension.matches(path),
              !path.hasPrefix(ImageMarkers.uploadsDirectory) else {
            return []
        }
        return [path]
    }

    private static func systemEffects(_ line: Line) -> [LineEffect] {
        let subtype = line["subtype"]?.stringValue ?? ""
        let content = line["content"]?.stringValue
        switch subtype {
        case "turn_duration":
            guard !line.isSubagent, let duration = line["durationMs"]?.intValue else { return [.turnEnded] }
            return [.item(line.item(.turnFooter(durationMs: duration))), .turnEnded]
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
    let isSubagent: Bool

    subscript(key: String) -> JSONValue? {
        object[key]
    }

    var isRoot: Bool {
        object["parentUuid"] == .null
    }

    var date: Date? {
        object["timestamp"]?.stringValue.flatMap(ProtocolDate.date(from:))
    }

    func item(_ kind: ChatItemKind, blockIndex: Int? = nil, imagePaths: [String] = []) -> ChatItem {
        let base = object["uuid"]?.stringValue ?? "line@\(offset)"
        let id = blockIndex.map { "\(base)#\($0)" } ?? base
        return ChatItem(id: id, at: timestamp, kind: kind, imagePaths: imagePaths)
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
