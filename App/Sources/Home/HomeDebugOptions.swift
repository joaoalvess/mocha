#if DEBUG
import Foundation
import MochaProtocol

struct HomeDebugOptions {
    var openDetailAgentId: AgentID?

    static let openDetailKey = "home-open-detail"

    static func current(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) -> HomeDebugOptions {
        var options = HomeDebugOptions()
        options.openDetailAgentId = (argumentDomain[openDetailKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return options
    }
}

@MainActor
enum HomeDebugLaunch {
    private static var consumed: Set<String> = []

    static func consume(_ key: String) -> Bool {
        consumed.insert(key).inserted
    }
}
#endif
