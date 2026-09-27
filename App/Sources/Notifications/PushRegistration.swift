import Foundation
import MochaClient
import MochaProtocol
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushRegistration {
    static let shared = PushRegistration()

    let environment: DetectedApnsEnvironment
    let registrationSource: ApnsRegistrationBox
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults

    init(environment: DetectedApnsEnvironment = ApnsEnvironmentDetector.detect(), defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
        let cached = defaults.data(forKey: Self.registrationKey)
            .flatMap { try? JSONDecoder().decode(ApnsRegistration.self, from: $0) }
            .flatMap { $0.env == environment.environment ? $0 : nil }
        registrationSource = ApnsRegistrationBox(cached)
    }

    func registerAtLaunch() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        await requestAuthorizationAndRegister()
    }

    func requestAuthorizationAndRegister() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let registration = ApnsRegistration(token: hex, env: environment.environment)
        registrationSource.update(registration)
        if let data = try? JSONEncoder().encode(registration) {
            defaults.set(data, forKey: Self.registrationKey)
        }
    }

    private static let registrationKey = "apns.registration"
}
