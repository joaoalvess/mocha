import Foundation
import MochaClient
import MochaDemo
import MochaProtocol
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

    static let demoPairingAge: TimeInterval = 2 * 24 * 60 * 60

    @MainActor
    static func make(for launch: LaunchConfiguration) -> AppStartup {
        guard let options = launch.demoOptions else {
            return .session(AppSession(
                connection: debugConnection(LiveConnection.make(), launch: launch),
                uploader: GatewayImageUploader(tokenStore: KeychainTokenStore()),
                imageLoader: GatewayImageLoader(tokenStore: KeychainTokenStore()),
                pairingDates: UserDefaultsPairingDateStore()
            ))
        }
        guard let demo = try? DemoServerConnection(options: options) else { return .demoUnavailable }
        let pairedAt = options.startsPaired ? Date().addingTimeInterval(-demoPairingAge) : nil
        let images = SimulatedImageLibrary()
        return .session(AppSession(
            connection: debugConnection(demo, launch: launch),
            uploader: SimulatedImageUploader(library: images),
            imageLoader: SimulatedImageLoader(library: images),
            pairingDates: InMemoryPairingDateStore(pairedAt: pairedAt)
        ))
    }

    private static func debugConnection(_ connection: any ServerConnection, launch: LaunchConfiguration) -> any ServerConnection {
        #if DEBUG
        guard let problem = launch.pairingProblem else { return connection }
        return PairingProblemConnection(base: connection, problem: problem)
        #else
        return connection
        #endif
    }
}
