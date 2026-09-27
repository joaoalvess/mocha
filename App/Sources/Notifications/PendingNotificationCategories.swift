import MochaClient
import UserNotifications

enum PendingNotificationCategories {
    static func make() -> Set<UNNotificationCategory> {
        [permission, question]
    }

    private static var permission: UNNotificationCategory {
        UNNotificationCategory(
            identifier: PendingNotificationCategory.permission,
            actions: [
                UNNotificationAction(
                    identifier: PendingNotificationAction.allow,
                    title: PendingText.allow,
                    options: [.authenticationRequired]
                ),
                UNNotificationAction(
                    identifier: PendingNotificationAction.deny,
                    title: PendingText.deny,
                    options: [.destructive]
                ),
            ],
            intentIdentifiers: []
        )
    }

    private static var question: UNNotificationCategory {
        UNNotificationCategory(
            identifier: PendingNotificationCategory.question,
            actions: [
                UNTextInputNotificationAction(
                    identifier: PendingNotificationAction.answer,
                    title: PendingText.answer,
                    options: [],
                    textInputButtonTitle: PendingText.send,
                    textInputPlaceholder: PendingText.answerPlaceholder
                ),
            ],
            intentIdentifiers: []
        )
    }
}
