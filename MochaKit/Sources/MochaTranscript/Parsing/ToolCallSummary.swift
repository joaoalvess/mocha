import Foundation

enum ToolCallSummary {
    static func summary(toolName: String, input: JSONValue?, cwd: String?) -> String {
        let value = specificValue(toolName: toolName, input: input, cwd: cwd) ?? firstStringValue(of: input) ?? ""
        return value.firstNonEmptyLine.truncated(toCharacters: TextLimits.summary)
    }

    private static func specificValue(toolName: String, input: JSONValue?, cwd: String?) -> String? {
        guard let input else { return nil }
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

    private static func nonEmpty(_ value: JSONValue?) -> String? {
        guard let string = value?.stringValue, !string.isBlank else { return nil }
        return string
    }

    private static func firstStringValue(of input: JSONValue?) -> String? {
        guard let members = input?.objectValue?.members else { return nil }
        for member in members {
            if let string = nonEmpty(member.value) { return string }
        }
        return nil
    }

    private static func relative(_ path: String, to cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return path }
        let prefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return path }
        return String(path.dropFirst(prefix.count))
    }
}
