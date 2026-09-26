public enum HookEventName: String, Sendable, CaseIterable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case stop = "Stop"
    case notification = "Notification"
    case permissionRequest = "PermissionRequest"

    public static let pathPrefix = "/hooks/"

    public var path: String {
        Self.pathPrefix + rawValue
    }

    var usesHttpHook: Bool {
        self == .permissionRequest
    }
}
