import Foundation

public enum SubagentType {
    public static let fallback = "general-purpose"

    public static func displayName(for rawType: String?) -> String {
        guard let rawType, !rawType.isEmpty else { return fallback }
        guard let separator = rawType.lastIndex(of: ":") else { return rawType }
        let name = rawType[rawType.index(after: separator)...]
        return name.isEmpty ? fallback : String(name)
    }
}

enum WorkflowName {
    static let fallback = "Workflow"

    static func name(script: String?, scriptPath: String?) -> String {
        if let script, let name = WorkflowScriptMeta.parse(script)?.name, !name.isEmpty {
            return name
        }
        if let scriptPath, let name = fileStem(of: scriptPath), !name.isEmpty {
            return name
        }
        return fallback
    }

    private static func fileStem(of path: String) -> String? {
        let fileName = URL(filePath: path).deletingPathExtension().lastPathComponent
        guard !fileName.isEmpty else { return nil }
        guard let suffix = fileName.range(of: "-wf_", options: .backwards) else { return fileName }
        return String(fileName[..<suffix.lowerBound])
    }
}
