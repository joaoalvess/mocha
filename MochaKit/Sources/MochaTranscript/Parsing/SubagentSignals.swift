import Foundation
import MochaProtocol

public enum SubagentFileEnding: Sendable, Equatable {
    case running
    case completed
    case failed(reason: String)
    case stopped
}

public struct SubagentFileScanner: Sendable {
    private struct PendingTool: Sendable {
        let id: String
        let activity: ToolActivity
    }

    private static let syntheticModel = "<synthetic>"
    private static let structuredOutputTool = "StructuredOutput"
    private static let interruptionMarkers: Set<String> = [
        "[Request interrupted by user]",
        "[Request interrupted by user for tool use]",
    ]

    public private(set) var toolUses = 0
    public private(set) var startedAt: Date?
    public private(set) var ending: SubagentFileEnding = .running
    public private(set) var endingAt: Date?
    private var forkToolUseId: String?
    private var pendingTools: [PendingTool] = []
    private var structuredOutputIds: Set<String> = []

    public init(forkToolUseId: String?) {
        self.forkToolUseId = forkToolUseId
    }

    public var activity: ToolActivity? {
        guard ending == .running else { return nil }
        return pendingTools.last?.activity
    }

    public var hasCrossedForkBoundary: Bool {
        forkToolUseId == nil
    }

    public mutating func consume(_ bytes: [UInt8]) {
        if let forkToolUseId {
            let parsed = TranscriptLineParser.parse(bytes, offset: 0, mode: .forkPrelude(toolUseId: forkToolUseId))
            guard parsed.crossesForkBoundary else { return }
            self.forkToolUseId = nil
            let date = parsed.date
            startedAt = startedAt ?? date
            ending = .running
            endingAt = date ?? endingAt
            return
        }
        guard let root = try? JSONParser.parse(bytes).objectValue, let type = root["type"]?.stringValue else { return }
        let date = root["timestamp"]?.stringValue.flatMap(ProtocolDate.date(from:))
        if startedAt == nil, let date {
            startedAt = date
        }
        guard type != "attachment" else { return }
        endingAt = date ?? endingAt
        switch type {
        case "assistant":
            ending = assistantEnding(root)
        case "user":
            ending = userEnding(root)
        default:
            ending = .running
        }
    }

    private mutating func assistantEnding(_ root: JSONObject) -> SubagentFileEnding {
        guard let message = root["message"] else { return .running }
        let blocks = message["content"]?.arrayValue ?? []
        let texts = blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }
        if root["isApiErrorMessage"]?.isTrue == true || message["model"]?.stringValue == Self.syntheticModel {
            let reason = (texts.isEmpty ? message["content"]?.stringValue.map { [$0] } ?? [] : texts)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(reason: reason)
        }
        let cwd = root["cwd"]?.stringValue
        for block in blocks where block["type"]?.stringValue == "tool_use" {
            toolUses += 1
            let id = block["id"]?.stringValue ?? ""
            let name = block["name"]?.stringValue ?? ""
            if name == Self.structuredOutputTool {
                structuredOutputIds.insert(id)
            }
            let summary = ToolCallSummary.summary(toolName: name, input: block["input"], cwd: cwd)
            pendingTools.append(PendingTool(id: id, activity: ToolActivity(toolName: name, summary: summary, status: .running)))
        }
        let hasText = texts.contains { !$0.isBlank } || message["content"]?.stringValue.map { !$0.isBlank } == true
        return message["stop_reason"]?.stringValue == "end_turn" && hasText ? .completed : .running
    }

    private mutating func userEnding(_ root: JSONObject) -> SubagentFileEnding {
        let content = root["message"]?["content"]
        if case .string(let text) = content {
            return Self.interruptionMarkers.contains(text) ? .stopped : .running
        }
        let blocks = content?.arrayValue ?? []
        let resultIds = blocks.compactMap { $0["type"]?.stringValue == "tool_result" ? $0["tool_use_id"]?.stringValue : nil }
        if !resultIds.isEmpty {
            let finished = Set(resultIds)
            pendingTools.removeAll { finished.contains($0.id) }
            return finished.isDisjoint(with: structuredOutputIds) ? .running : .completed
        }
        if blocks.count == 1,
           blocks[0]["type"]?.stringValue == "text",
           let text = blocks[0]["text"]?.stringValue,
           Self.interruptionMarkers.contains(text) {
            return .stopped
        }
        return .running
    }
}

public enum SubagentSignal: Sendable, Equatable {
    case notification(TaskNotification, at: Date?, enqueued: Bool)
    case workflowLaunch(toolUseId: String, script: String?, scriptPath: String?, at: Date?)
    case workflowLaunched(toolUseId: String, runId: String, taskId: String?, workflowName: String?, scriptPath: String?)
}

public enum SubagentSignalScanner {
    private static let markers: [[UInt8]] = [
        Array("task-notification".utf8),
        Array("\"Workflow\"".utf8),
        Array("\"runId\"".utf8),
    ]

    public static func mayContainSignal(_ bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBytes { buffer in
            markers.contains { contains($0, in: buffer) }
        }
    }

    public static func signals(in bytes: [UInt8]) -> [SubagentSignal] {
        guard mayContainSignal(bytes),
              let root = try? JSONParser.parse(bytes).objectValue,
              let type = root["type"]?.stringValue else {
            return []
        }
        let date = root["timestamp"]?.stringValue.flatMap(ProtocolDate.date(from:))
        switch type {
        case "queue-operation":
            guard root["operation"]?.stringValue == "enqueue", let content = root["content"]?.stringValue else { return [] }
            return notifications(in: content, at: date, enqueued: true)
        case "attachment":
            guard let attachment = root["attachment"],
                  attachment["type"]?.stringValue == "queued_command",
                  attachment["commandMode"]?.stringValue == "task-notification",
                  let prompt = attachment["prompt"] else {
                return []
            }
            return notifications(in: plainText(prompt), at: date, enqueued: false)
        case "user":
            return userSignals(root, at: date)
        case "assistant":
            let blocks = root["message"]?["content"]?.arrayValue ?? []
            return blocks.compactMap { block in
                guard block["type"]?.stringValue == "tool_use",
                      block["name"]?.stringValue == "Workflow",
                      let id = block["id"]?.stringValue else {
                    return nil
                }
                let input = block["input"]
                return .workflowLaunch(
                    toolUseId: id,
                    script: input?["script"]?.stringValue,
                    scriptPath: input?["scriptPath"]?.stringValue,
                    at: date
                )
            }
        default:
            return []
        }
    }

    private static func userSignals(_ root: JSONObject, at date: Date?) -> [SubagentSignal] {
        let content = root["message"]?["content"]
        if root["origin"]?["kind"]?.stringValue == "task-notification", case .string(let text) = content {
            return notifications(in: text, at: date, enqueued: false)
        }
        guard let result = root["toolUseResult"], let runId = result["runId"]?.stringValue else { return [] }
        let blocks = content?.arrayValue ?? []
        guard let toolUseId = blocks.lazy.compactMap({ $0["type"]?.stringValue == "tool_result" ? $0["tool_use_id"]?.stringValue : nil }).first else {
            return []
        }
        return [.workflowLaunched(
            toolUseId: toolUseId,
            runId: runId,
            taskId: result["taskId"]?.stringValue,
            workflowName: result["workflowName"]?.stringValue,
            scriptPath: result["scriptPath"]?.stringValue
        )]
    }

    private static func notifications(in text: String, at date: Date?, enqueued: Bool) -> [SubagentSignal] {
        TaskNotification.parse(text)
            .filter { $0.kind != .other }
            .map { .notification($0, at: date, enqueued: enqueued) }
    }

    private static func plainText(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): text
        case .array(let blocks): blocks.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
        default: ""
        }
    }

    private static func contains(_ needle: [UInt8], in bytes: UnsafeRawBufferPointer) -> Bool {
        guard let base = bytes.baseAddress, bytes.count >= needle.count else { return false }
        return needle.withUnsafeBytes { pattern in
            guard let patternBase = pattern.baseAddress else { return false }
            return memmem(base, bytes.count, patternBase, pattern.count) != nil
        }
    }
}
