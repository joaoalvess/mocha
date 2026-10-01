public enum ModelAlias: String, Codable, Sendable, Hashable, CaseIterable {
    case fable, opus, sonnet, haiku
}

public enum EffortLevel: String, Codable, Sendable, Hashable, CaseIterable {
    case low, medium, high, xhigh, max
}

public enum PermissionModeTarget: String, Codable, Sendable, Hashable, CaseIterable {
    case `default`, acceptEdits, plan, auto
}

public struct ModelOption: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var displayName: String
    public var isDefault: Bool
    public var defaultEffort: String?
    public var efforts: [EffortOption]

    public init(id: String, displayName: String, isDefault: Bool = false, defaultEffort: String? = nil, efforts: [EffortOption] = []) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
        self.defaultEffort = defaultEffort
        self.efforts = efforts
    }
}

public struct EffortOption: Codable, Sendable, Hashable, Identifiable {
    public var level: String
    public var description: String?

    public var id: String { level }

    public init(level: String, description: String? = nil) {
        self.level = level
        self.description = description
    }
}
