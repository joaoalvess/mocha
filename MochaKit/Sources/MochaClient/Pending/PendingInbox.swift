import Foundation
import MochaProtocol

public enum PendingSendOutcome: Sendable, Equatable {
    case accepted
    case gone
    case failed(String)
}

public struct PendingInbox: Sendable, Equatable {
    public private(set) var requests: [PendingRequest] = []
    public private(set) var sending: Set<RequestID> = []
    public private(set) var answered: Set<RequestID> = []
    public private(set) var failures: [RequestID: String] = [:]

    public init(requests: [PendingRequest] = []) {
        replace(with: requests)
    }

    public var visible: [PendingRequest] {
        requests
            .filter { !answered.contains($0.id) }
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public var count: Int {
        visible.count
    }

    public func request(forAgent agentId: AgentID) -> PendingRequest? {
        visible.first { $0.agentId == agentId }
    }

    public func isSending(_ requestId: RequestID) -> Bool {
        sending.contains(requestId)
    }

    public func failure(for requestId: RequestID) -> String? {
        failures[requestId]
    }

    public mutating func replace(with requests: [PendingRequest]) {
        self.requests = requests
        let ids = Set(requests.map(\.id))
        sending.formIntersection(ids)
        answered.formIntersection(ids)
        failures = failures.filter { ids.contains($0.key) }
    }

    public mutating func beginSending(_ requestId: RequestID) -> Bool {
        guard contains(requestId), !sending.contains(requestId), !answered.contains(requestId) else { return false }
        sending.insert(requestId)
        failures[requestId] = nil
        return true
    }

    public mutating func finishSending(_ requestId: RequestID, outcome: PendingSendOutcome) {
        sending.remove(requestId)
        guard contains(requestId) else { return }
        switch outcome {
        case .accepted, .gone:
            answered.insert(requestId)
        case .failed(let message):
            failures[requestId] = message
        }
    }

    private func contains(_ requestId: RequestID) -> Bool {
        requests.contains { $0.id == requestId }
    }
}
