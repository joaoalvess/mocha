import Foundation
import MochaProtocol

extension SessionHub {
    func startPendingUpdates() async {
        guard let pending else { return }
        pendingRequests = await pending.requests
        let updates = pending.updates()
        sessionServiceTasks.append(Task { [weak self] in
            for await requests in updates {
                await self?.pendingChanged(requests)
            }
        })
    }

    func pendingCounts() -> [AgentID: Int] {
        pendingRequests.reduce(into: [:]) { counts, request in
            counts[request.agentId, default: 0] += 1
        }
    }

    func sendPending(to clientId: UUID) {
        guard pending != nil else { return }
        send(.pending(requests: pendingRequests), to: clientId)
    }

    func respond(to requestId: RequestID, with response: PendingResponse, id: String, clientId: UUID) async {
        guard let pending else {
            send(.unknownType("respond"), id: id, to: clientId)
            return
        }
        do {
            try await pending.respond(to: requestId, with: response)
            send(.ack(), id: id, to: clientId)
        } catch {
            switch error {
            case .requestNotFound:
                send(.requestNotFound, id: id, to: clientId)
            case .invalidPayload(let message):
                send(.invalidResponse(message), id: id, to: clientId)
            }
        }
    }

    private func pendingChanged(_ requests: [PendingRequest]) {
        guard requests != pendingRequests else { return }
        pendingRequests = requests
        broadcast(.pending(requests: requests))
        scheduleTreeFlush()
    }
}
