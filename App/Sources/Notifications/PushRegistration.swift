import Foundation
import MochaProtocol
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushRegistration {
    static let shared = PushRegistration()

    let environment = ApnsEnvironmentDetector.detect()
    private(set) var deviceTokenHex: String?
    private(set) var lastError: String?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    var registration: ApnsRegistration? {
        deviceTokenHex.map { ApnsRegistration(token: $0, env: environment.environment) }
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorizationAndRegister() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastError = error.localizedDescription
        }
        await refreshAuthorization()
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        deviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastError = nil
    }

    func didFailToRegister(error: any Error) {
        lastError = error.localizedDescription
    }
}
