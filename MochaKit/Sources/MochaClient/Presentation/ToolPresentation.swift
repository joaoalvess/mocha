public enum ToolIcon: Sendable, Equatable {
    case shell
    case document
    case pencil
    case sparkles
}

public enum ToolPresentation {
    public static func displayName(for toolName: String) -> String {
        displayNames[toolName] ?? toolName
    }

    public static func icon(for toolName: String) -> ToolIcon {
        switch toolName {
        case "Bash", "BashOutput", "KillShell", "Shell": .shell
        case "Read", "NotebookRead": .document
        case "Edit", "MultiEdit", "Write", "NotebookEdit": .pencil
        default: .sparkles
        }
    }

    private static let displayNames = ["Bash": "Shell"]
}
