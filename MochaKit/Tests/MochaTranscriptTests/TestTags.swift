import Foundation
import Testing

extension Tag {
    @Tag static var integration: Self
}

enum IntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MOCHA_INTEGRATION"] == "1"
    }
}
