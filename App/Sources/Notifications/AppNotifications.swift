import Foundation
import MochaClient
import UserNotifications

@MainActor
enum AppNotifications {
    static let taps = NotificationTapRelay()
    private static let delegate = AlertNotificationDelegate()

    static func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories(Set(AlertCategory.all.map {
            UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [])
        }).union(PendingNotificationCategories.make()))
        PushRegistration.shared.registerAtLaunch()
        #if DEBUG
        NotificationTapDebugLaunch.schedule()
        #endif
    }

    static func connectionOpened() {
        guard !ProcessInfo.processInfo.arguments.contains(LaunchConfiguration.demoFlag) else { return }
        Task { await PushRegistration.shared.requestAuthorizationIfNeeded() }
    }
}
