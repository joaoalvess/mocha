import Foundation
import Observation

@MainActor
@Observable
final class PushRegistration {
    static let shared = PushRegistration()

    private(set) var deviceTokenHex: String?
    private(set) var lastError: String?

    func didRegister(deviceToken: Data) {
        deviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastError = nil
    }

    func didFailToRegister(error: any Error) {
        lastError = error.localizedDescription
    }
}
