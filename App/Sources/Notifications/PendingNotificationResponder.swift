import Foundation
import MochaClient
import os
import UserNotifications

enum PendingNotificationResponder {
    private static let logger = Logger(subsystem: "com.joaoalves.mocha", category: "notifications")

    static func send(_ reply: PendingNotificationReply, responder: any PendingResponding = GatewayPendingResponder(tokenStore: KeychainTokenStore())) async {
        let result = await responder.respond(to: reply.requestId, with: reply.response)
        logger.info("notification \(reply.response.type, privacy: .public) for \(reply.requestId, privacy: .public): \(String(describing: result), privacy: .public)")
        guard let notice = PendingText.failureNotice(for: result) else { return }
        await post(notice, for: reply)
    }

    private static func post(_ notice: PendingNotice, for reply: PendingNotificationReply) async {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        if let agentId = reply.agentId {
            content.userInfo = [AlertPayload.agentIdKey: agentId]
            content.threadIdentifier = agentId
        }
        let request = UNNotificationRequest(identifier: "respond-failed-\(reply.requestId)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("failed to post the respond failure notice: \(error.localizedDescription, privacy: .public)")
        }
    }
}
