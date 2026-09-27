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
    static let planCategory = "PLAN"

    static func title(_ kind: PushAlertKind, workspaceLabel: String?) -> String {
        let base = switch kind {
        case .turnDone: "Claude terminou"
        case .needsInput: "Claude precisa de você"
        }
        return title(base, workspaceLabel: workspaceLabel)
    }

    static func title(_ base: String, workspaceLabel: String?) -> String {
        guard let label = workspaceLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return base }
        return base + " · " + label
    }

    static func turnDoneBody(_ lastAssistantMessage: String?) -> String {
        let preview = PlainText.preview(fromMarkdown: lastAssistantMessage ?? "", limit: bodyLimit)
        return preview.isEmpty ? turnDoneFallback : preview
    }

    static let inlineQuestionByteLimit = 2_000

    static func pendingCategory(_ request: PermissionRequestHook) -> String {
        if request.toolName == PendingRequestFactory.planToolName { return planCategory }
        guard request.toolName == PendingRequestFactory.questionToolName else { return permissionCategory }
        return inlineQuestion(request) == nil ? PushAlertKind.needsInput.category : questionCategory
    }

    static func inlineQuestion(_ request: PermissionRequestHook) -> String? {
        guard request.toolName == PendingRequestFactory.questionToolName,
              let questions = request.toolInput["questions"]?.arrayValue, questions.count == 1,
              questions[0]["multiSelect"]?.boolValue != true,
              let question = nonEmpty(questions[0]["question"]), question.utf8.count <= inlineQuestionByteLimit
        else { return nil }
        return question
    }

    static func needsInputBody(_ request: PermissionRequestHook) -> String {
        if let question = inlineQuestion(request) { return question }
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
        case PendingRequestFactory.planToolName:
            return nonEmpty(input["plan"]).map { PlainText.preview(fromMarkdown: firstNonEmptyLine($0)) }
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
