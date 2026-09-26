import MochaDemo
import SwiftUI

@main
struct MochaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let launch: LaunchConfiguration
    @State private var startup: AppStartup

    init() {
        let launch = LaunchConfiguration.current()
        self.launch = launch
        _startup = State(initialValue: AppStartup.make(for: launch))
    }

    var body: some Scene {
        WindowGroup {
            RootView(launch: launch, startup: startup)
                .preferredColorScheme(.dark)
        }
    }
}

enum AppStartup {
    case session(AppSession)
    case demoUnavailable
    case awaitingConnection

    @MainActor
    static func make(for launch: LaunchConfiguration) -> AppStartup {
        guard let options = launch.demoOptions else { return .awaitingConnection }
        guard let connection = try? DemoServerConnection(options: options) else { return .demoUnavailable }
        return .session(AppSession(connection: connection))
    }
}
