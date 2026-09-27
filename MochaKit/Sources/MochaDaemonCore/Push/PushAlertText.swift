import Foundation
import MochaTranscript

public enum PushAlertKind: String, Sendable, Equatable {
    case turnDone
    case needsInput

    var category: String {
        switch self {
        case .turnDone: "TURN_DONE"
        case .needsInput: "NEEDS_INPUT"
        }
    }

    var interruptionLevel: ApnsInterruptionLevel? {
        switch self {
        case .turnDone: nil
        case .needsInput: .timeSensitive
        }
    }
}

enum PushAlertText {
    static let bodyLimit = 180
    static let summaryLimit = 120
    static let turnDoneFallback = "Turno concluído."
    static let secondaryBody = "Esperando uma resposta no terminal."
    static let permissionCategory = "PERMISSION"
    static let questionCategory = "QUESTION"

    static func title(_ kind: PushAlertKind, workspaceLabel: String?) -> String {
        let base = switch kind {
        case .turnDone: "Claude terminou"
        case .needsInput: "Claude precisa de você"
        }
        guard let label = workspaceLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return base }
        return base + " · " + label
    }

    static func turnDoneBody(_ lastAssistantMessage: String?) -> String {
        let preview = PlainText.preview(fromMarkdown: lastAssistantMessage ?? "", limit: bodyLimit)
        return preview.isEmpty ? turnDoneFallback : preview
    }

    static func pendingCategory(_ request: PermissionRequestHook) -> String {
        request.toolName == PendingRequestFactory.questionToolName ? questionCategory : permissionCategory
    }

    static func needsInputBody(_ request: PermissionRequestHook) -> String {
        if request.toolName == "AskUserQuestion", let question = nonEmpty(request.toolInput["questions"]?.arrayValue?.first?["question"]) {
            return PlainText.preview(fromMarkdown: question, limit: bodyLimit)
        }
        let summary = self.summary(toolName: request.toolName, input: request.toolInput, cwd: request.context.cwd)
        return summary.isEmpty ? request.toolName : summary
    }

    static func summary(toolName: String, input: OrderedJSON, cwd: String?) -> String {
        let value = specificValue(toolName: toolName, input: input, cwd: cwd) ?? firstStringValue(of: input) ?? ""
        return String(firstNonEmptyLine(value).prefix(summaryLimit))
    }

    private static func specificValue(toolName: String, input: OrderedJSON, cwd: String?) -> String? {
        switch toolName {
        case "Bash":
            return nonEmpty(input["command"])
        case "Read", "Write", "Edit", "NotebookEdit":
            return (nonEmpty(input["file_path"]) ?? nonEmpty(input["notebook_path"])).map { relative($0, to: cwd) }
        case "Grep", "Glob":
            return nonEmpty(input["pattern"])
        case "WebFetch":
            return nonEmpty(input["url"])
        case "WebSearch", "ToolSearch":
            return nonEmpty(input["query"])
        case "Agent":
            return nonEmpty(input["description"])
        case "AskUserQuestion":
            return nonEmpty(input["questions"]?.arrayValue?.first?["question"])
        case "ExitPlanMode":
            return nonEmpty(input["plan"])
        case "Skill":
            return nonEmpty(input["skill"])
        case "TaskOutput", "TaskStop":
            return nonEmpty(input["task_id"])
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: OrderedJSON?) -> String? {
        guard let string = value?.stringValue, !string.allSatisfy(\.isWhitespace) else { return nil }
        return string
    }

    private static func firstStringValue(of input: OrderedJSON) -> String? {
        for member in input.members ?? [] {
            if let string = nonEmpty(member.value) { return string }
        }
        return nil
    }

    private static func firstNonEmptyLine(_ text: String) -> String {
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private static func relative(_ path: String, to cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return path }
        let prefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return path }
        return String(path.dropFirst(prefix.count))
    }
}
