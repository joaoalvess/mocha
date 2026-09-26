#if DEBUG
import Foundation
import MochaProtocol

struct DrawerDebugOptions {
    var newTabWorkspaceId: WorkspaceID?
    var newTabDelay: Duration = .zero
    var reopenAfter: Duration?

    static let newTabKey = "drawer-new-tab"
    static let newTabDelayKey = "drawer-new-tab-delay"
    static let reopenAfterKey = "drawer-reopen-after"

    static func current(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) -> DrawerDebugOptions {
        var options = DrawerDebugOptions()
        options.newTabWorkspaceId = (argumentDomain[newTabKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        options.newTabDelay = duration(argumentDomain[newTabDelayKey]) ?? .zero
        options.reopenAfter = duration(argumentDomain[reopenAfterKey])
        return options
    }

    private static func duration(_ value: Any?) -> Duration? {
        (value as? String).flatMap(Double.init).map { .milliseconds(Int($0 * 1_000)) }
    }
}

@MainActor
enum DrawerDebugLaunch {
    private static var consumed: Set<String> = []

    static func consume(_ key: String) -> Bool {
        consumed.insert(key).inserted
    }
}
#endif
