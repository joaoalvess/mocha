import Foundation
import MochaProtocol

struct DetectedApnsEnvironment: Equatable, Sendable {
    let environment: ApnsEnvironment
    let source: String
}

enum ApnsEnvironmentDetector {
    static func detect(bundle: Bundle = .main) -> DetectedApnsEnvironment {
        #if targetEnvironment(simulator)
        return DetectedApnsEnvironment(environment: .sandbox, source: "simulador")
        #else
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return DetectedApnsEnvironment(environment: .production, source: "sem perfil embutido (TestFlight ou App Store)")
        }
        guard let data = try? Data(contentsOf: url), let value = apsEnvironment(inProvisioningProfile: data) else {
            return DetectedApnsEnvironment(environment: .production, source: "perfil embutido sem aps-environment")
        }
        return DetectedApnsEnvironment(
            environment: value == "development" ? .sandbox : .production,
            source: "perfil embutido: aps-environment = \(value)"
        )
        #endif
    }

    static func apsEnvironment(inProvisioningProfile data: Data) -> String? {
        guard
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
            let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil),
            let profile = plist as? [String: Any],
            let entitlements = profile["Entitlements"] as? [String: Any]
        else { return nil }
        return entitlements["aps-environment"] as? String
    }
}
