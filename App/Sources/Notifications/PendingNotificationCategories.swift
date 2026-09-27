import MochaClient
import UserNotifications

enum PendingNotificationCategories {
    static func make() -> Set<UNNotificationCategory> {
        [approval(PendingNotificationCategory.permission, allowTitle: PendingText.allow), approval(PendingNotificationCategory.plan, allowTitle: PendingText.approve), question]
    }

    private static func approval(_ identifier: String, allowTitle: String) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: identifier,
            actions: [
                UNNotificationAction(
                    identifier: PendingNotificationAction.allow,
                    title: allowTitle,
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
