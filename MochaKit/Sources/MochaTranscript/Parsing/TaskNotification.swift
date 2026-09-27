import Foundation
import MochaProtocol

public struct TaskNotification: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case agent
        case workflow
        case other
    }

    public var taskId: String?
    public var toolUseId: String?
    public var status: String?
    public var summary: String?
    public var note: String?
    public var toolUses: Int?
    public var durationMs: Int?
    public var agentCount: Int?

    public init(
        taskId: String? = nil,
        toolUseId: String? = nil,
        status: String? = nil,
        summary: String? = nil,
        note: String? = nil,
        toolUses: Int? = nil,
        durationMs: Int? = nil,
        agentCount: Int? = nil
    ) {
        self.taskId = taskId
        self.toolUseId = toolUseId
        self.status = status
        self.summary = summary
        self.note = note
        self.toolUses = toolUses
        self.durationMs = durationMs
        self.agentCount = agentCount
    }

    static let interimMarker = "stopped with background work of its own still running"
    private static let failureMarker = "failed: "
    private static let openTag = "<task-notification>"
    private static let closeTag = "</task-notification>"

    public var kind: Kind {
        guard let taskId else { return .other }
        if Self.isAgentId(taskId) { return .agent }
        if Self.isWorkflowTaskId(taskId) { return .workflow }
        return .other
    }

    public var isInterim: Bool {
        note?.contains(Self.interimMarker) ?? false
    }

    public var subagentStatus: SubagentStatus? {
        switch status {
        case "completed": isInterim ? .running : .completed
        case "failed": .failed
        case "killed": .stopped
        default: nil
        }
    }

    public var workflowStatus: WorkflowStatus? {
        switch status {
        case "completed": .completed
        case "failed": .failed
        case "killed": .stopped
        default: nil
        }
    }

    public var failureReason: String? {
        guard status == "failed", let summary else { return nil }
        let marker = summary.range(of: "\" \(Self.failureMarker)") ?? summary.range(of: Self.failureMarker)
        guard let marker else { return summary }
        let reason = summary[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? summary : reason
    }

    public static func parse(_ text: String) -> [TaskNotification] {
        var notifications: [TaskNotification] = []
        var searchStart = text.startIndex
        while let open = text.range(of: openTag, range: searchStart..<text.endIndex) {
            let rest = open.upperBound..<text.endIndex
            let nextOpen = text.range(of: openTag, range: rest)?.lowerBound ?? text.endIndex
            let close = text.range(of: closeTag, range: open.upperBound..<nextOpen)
            let body = text[open.upperBound..<(close?.lowerBound ?? nextOpen)]
            notifications.append(TaskNotification(block: body))
            searchStart = close?.upperBound ?? nextOpen
        }
        return notifications
    }

    init(block: Substring) {
        let fields = Self.removing(tag: "result", from: block)
        let usage = Self.value(of: "usage", in: fields)
        self.init(
            taskId: Self.value(of: "task-id", in: fields).flatMap(Self.nonEmpty),
            toolUseId: Self.value(of: "tool-use-id", in: fields).flatMap(Self.nonEmpty),
            status: Self.value(of: "status", in: fields).flatMap(Self.nonEmpty),
            summary: Self.value(of: "summary", in: fields).flatMap(Self.nonEmpty),
            note: Self.value(of: "note", in: fields).flatMap(Self.nonEmpty),
            toolUses: usage.flatMap { Self.integer(of: "tool_uses", in: $0) },
            durationMs: usage.flatMap { Self.integer(of: "duration_ms", in: $0) },
            agentCount: usage.flatMap { Self.integer(of: "agent_count", in: $0) }
        )
    }

    private static func value(of tag: String, in text: Substring) -> Substring? {
        guard let open = text.range(of: "<\(tag)>") else { return nil }
        let rest = text[open.upperBound...]
        guard let close = rest.range(of: "</\(tag)>") else { return rest }
        return rest[..<close.lowerBound]
    }

    private static func removing(tag: String, from text: Substring) -> Substring {
        guard let open = text.range(of: "<\(tag)>") else { return text }
        guard let close = text[open.upperBound...].range(of: "</\(tag)>") else { return text[..<open.lowerBound] }
        return Substring(text[..<open.lowerBound] + text[close.upperBound...])
    }

    private static func integer(of tag: String, in text: Substring) -> Int? {
        value(of: tag, in: text).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func nonEmpty(_ text: Substring) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isAgentId(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard bytes.count == 17, bytes[0] == UInt8(ascii: "a") else { return false }
        return bytes.dropFirst().allSatisfy { isDigit($0) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0) }
    }

    static func isWorkflowTaskId(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard bytes.count == 9, bytes[0] == UInt8(ascii: "w") else { return false }
        return bytes.dropFirst().allSatisfy { isDigit($0) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
