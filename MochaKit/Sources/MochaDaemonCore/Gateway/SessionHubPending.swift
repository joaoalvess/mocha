import Foundation
import MochaProtocol

extension SessionHub {
    static let codexRequestPrefix = "codex:"

    func startPendingUpdates() async {
        guard let pending else { return }
        storePendingRequests = await pending.requests
        pendingRequests = storePendingRequests
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
        guard pending != nil || requestId.hasPrefix(Self.codexRequestPrefix) else {
            send(.unknownType("respond"), id: id, to: clientId)
            return
        }
        do {
            try await answer(requestId, with: response)
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

    func answer(_ requestId: RequestID, with response: PendingResponse) async throws(PendingRespondError) {
        if requestId.hasPrefix(Self.codexRequestPrefix) {
            try await answerCodex(requestId, with: response)
            return
        }
        guard let pending else { throw PendingRespondError.requestNotFound }
        try await pending.respond(to: requestId, with: response)
    }

    func mergeDecisions() {
        pendingDecisions = storePendingDecisions.merging(codexDecisions) { _, codex in codex }
    }

    func mergePending() {
        let merged = codexPendingRequests.isEmpty
            ? storePendingRequests
            : (storePendingRequests + codexPendingRequests).sorted { $0.createdAt < $1.createdAt }
        guard merged != pendingRequests else { return }
        pendingRequests = merged
        broadcast(.pending(requests: merged))
        scheduleTreeFlush()
    }

    private func pendingChanged(_ requests: [PendingRequest]) async {
        guard requests != storePendingRequests else { return }
        storePendingDecisions = await pending?.decisions ?? [:]
        mergeDecisions()
        storePendingRequests = requests
        mergePending()
    }
}
