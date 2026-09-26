import Foundation
import MochaDemo

struct LaunchConfiguration: Equatable {
    var demoOptions: DemoOptions?
    #if DEBUG
    var probe: DebugProbe?
    var preview: DebugPreview?
    #endif

    static let demoFlag = "-demo"
    static let demoScriptFlag = "-demo-script"
    static let demoUnpairedFlag = "-demo-unpaired"

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        argumentDomain: [String: Any] = LaunchArguments.argumentDomain()
    ) -> LaunchConfiguration {
        var configuration = LaunchConfiguration()
        if arguments.contains(demoFlag) {
            configuration.demoOptions = DemoOptions(
                startsPaired: !arguments.contains(demoUnpairedFlag),
                runsScript: arguments.contains(demoScriptFlag)
            )
        }
        #if DEBUG
        configuration.probe = (argumentDomain[DebugProbe.argumentKey] as? String).flatMap(DebugProbe.init(rawValue:))
        configuration.preview = (argumentDomain[DebugPreview.argumentKey] as? String).flatMap(DebugPreview.init(rawValue:))
        #endif
        return configuration
    }
}

enum LaunchArguments {
    static func argumentDomain(_ defaults: UserDefaults = .standard) -> [String: Any] {
        defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    }
}

#if DEBUG
enum DebugProbe: String {
    case push
    case gateway

    static let argumentKey = "probe"
}

enum DebugPreview: String {
    case designSystem = "design-system"
    case markdown

    static let argumentKey = "preview"
}
#endif
