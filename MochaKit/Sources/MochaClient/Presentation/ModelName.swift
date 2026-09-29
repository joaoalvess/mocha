public enum ModelName {
    public static func abbreviated(_ model: String) -> String {
        var name = model
        if name.hasPrefix(claudePrefix) {
            name.removeFirst(claudePrefix.count)
        }
        if let dateSuffix = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name.removeSubrange(dateSuffix)
        }
        return name
    }

    private static let claudePrefix = "claude-"
}

extension ModelName {
    public static func withEffort(_ model: String, effort: String?) -> String {
        let name = abbreviated(model)
        guard let effort, !effort.isEmpty, !name.isEmpty else { return name }
        return "\(name) · \(effort)"
    }
}
