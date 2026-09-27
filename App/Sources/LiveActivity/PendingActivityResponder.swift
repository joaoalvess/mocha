import Foundation
import MochaClient

enum PendingActivityResponder {
    static func respond(_ choice: AgentsActivityChoice, requestId: String, agentId: String) async {
        let reply = PendingNotificationReply(requestId: requestId, agentId: agentId, response: choice.response)
        let result = await PendingNotificationResponder.send(reply)
        guard AgentsActivityReply.clearsPending(after: result) else { return }
        await AgentsActivityController.clearPending(requestId)
    }
}
