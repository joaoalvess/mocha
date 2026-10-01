import MochaClient
import MochaProtocol
import SwiftUI

struct PendingChatCard: View {
    let session: AppSession
    let request: PendingRequest

    var body: some View {
        PendingRequestCard(
            request: request,
            heading: .chat(session.provider(of: .agent(request.agentId))),
            isSending: session.pending.isSending(request.id),
            failure: session.pending.failure(for: request.id)
        ) { response in
            session.respond(to: request.id, with: response)
        }
        .id(request.id)
    }
}
