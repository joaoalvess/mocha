public enum ModelAlias: String, Codable, Sendable, Hashable, CaseIterable {
    case fable, opus, sonnet, haiku
}

public enum EffortLevel: String, Codable, Sendable, Hashable, CaseIterable {
    case low, medium, high, xhigh, max
}

public enum PermissionModeTarget: String, Codable, Sendable, Hashable, CaseIterable {
    case `default`, acceptEdits, plan, auto
}
