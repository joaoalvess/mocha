import Foundation
import MochaClient
import UIKit

enum LiveConnection {
    @MainActor
    static func make() -> ConnectionManager {
        ConnectionManager(
            configuration: ConnectionConfiguration(deviceName: UIDevice.current.name, appVersion: AppVersion.current.marketing),
            tokenStore: KeychainTokenStore(),
            apnsRegistration: PushRegistration.shared.registrationSource
        )
    }
}

struct AppVersion: Equatable {
    var marketing: String
    var build: String

    static var current: AppVersion {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppVersion(
            marketing: info["CFBundleShortVersionString"] as? String ?? "—",
            build: info["CFBundleVersion"] as? String ?? "—"
        )
    }

    var text: String {
        "\(marketing) (\(build))"
    }
}
