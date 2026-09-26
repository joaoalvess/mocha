import Foundation
import MochaDemo

struct LaunchConfiguration: Equatable {
    var demoOptions: DemoOptions?
    var demoEmpty = false
    #if DEBUG
    var probe: DebugProbe?
    var preview: DebugPreview?
    var openURL: URL?
    var opensDrawer = false
    #endif

    static let demoFlag = "-demo"
    static let demoScriptFlag = "-demo-script"
    static let demoUnpairedFlag = "-demo-unpaired"
    static let demoEmptyFlag = "-demo-empty"
    static let demoOfflineFlag = "-demo-offline"
    #if DEBUG
    static let openDrawerFlag = "-open-drawer"
    #endif

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        argumentDomain: [String: Any] = LaunchArguments.argumentDomain()
    ) -> LaunchConfiguration {
        var configuration = LaunchConfiguration()
        if arguments.contains(demoFlag) {
            configuration.demoOptions = DemoOptions(
                startsPaired: !arguments.contains(demoUnpairedFlag),
                runsScript: arguments.contains(demoScriptFlag),
                isEmpty: arguments.contains(demoEmptyFlag),
                dropsConnectionAfterTree: arguments.contains(demoOfflineFlag)
            )
            configuration.demoEmpty = arguments.contains(demoEmptyFlag)
        }
        #if DEBUG
        configuration.probe = (argumentDomain[DebugProbe.argumentKey] as? String).flatMap(DebugProbe.init(rawValue:))
        configuration.preview = (argumentDomain[DebugPreview.argumentKey] as? String).flatMap(DebugPreview.init(rawValue:))
        configuration.openURL = (argumentDomain[LaunchArguments.openURLKey] as? String).flatMap(URL.init(string:))
        configuration.opensDrawer = arguments.contains(openDrawerFlag)
        #endif
        return configuration
    }
}

enum LaunchArguments {
    static let openURLKey = "open-url"

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
