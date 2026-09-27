import Foundation
import MochaDaemonCore
import MochaProtocol
import Synchronization

public final class FakeSubagentProvider: SubagentProviding {
    private struct State {
        var states: [String: SubagentState] = [:]
        var workflows: [String: WorkflowState] = [:]
        var counts: [String: Int] = [:]
        var lists: [String: [SubagentSummary]] = [:]
        var transcripts: [String: SubagentTranscript] = [:]
        var observed: [Set<String>] = []
        var listRequests: [String] = []
        var subscribers: [UUID: AsyncStream<SubagentEvent>.Continuation] = [:]
        var observeWaiters: [(predicate: @Sendable (Set<String>) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    public init() {}

    public func events() -> AsyncStream<SubagentEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SubagentEvent.self, bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.subscribers.removeValue(forKey: id) }
        }
        state.withLock { $0.subscribers[id] = continuation }
        return stream
    }

    public func observe(sessions: Set<String>) async {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.observed.append(sessions)
            let matched = state.observeWaiters.filter { $0.predicate(sessions) }
            state.observeWaiters.removeAll { $0.predicate(sessions) }
            return matched.map(\.continuation)
        }
        for continuation in ready {
            continuation.resume()
        }
    }

    public func runningCount(session sessionId: String) async -> Int {
        state.withLock { $0.counts[sessionId] ?? 0 }
    }

    public func subagents(session sessionId: String) async -> [SubagentSummary] {
        state.withLock { state in
            state.listRequests.append(sessionId)
            return state.lists[sessionId] ?? []
        }
    }

    public func state(_ agentId: String) async -> SubagentState? {
        state.withLock { $0.states[agentId] }
    }

    public func workflow(_ runId: String) async -> WorkflowState? {
        state.withLock { $0.workflows[runId] }
    }

    public func transcript(session sessionId: String, agentId: String) async -> SubagentTranscript? {
        state.withLock { $0.transcripts["\(sessionId)/\(agentId)"] }
    }

    public func publish(_ subagent: SubagentState) {
        publish(.subagent(subagent)) { $0.states[subagent.agentId] = subagent }
    }

    public func publish(_ workflow: WorkflowState) {
        publish(.workflow(workflow)) { $0.workflows[workflow.runId] = workflow }
    }

    public func publishRunningCount(_ count: Int, session sessionId: String) {
        publish(.runningCount(sessionId: sessionId, count: count)) { $0.counts[sessionId] = count }
    }

    public func setList(_ items: [SubagentSummary], session sessionId: String) {
        state.withLock { $0.lists[sessionId] = items }
    }

    public func setTranscript(_ transcript: SubagentTranscript, session sessionId: String) {
        state.withLock { $0.transcripts["\(sessionId)/\(transcript.agentId)"] = transcript }
    }

    public var observedSessions: [Set<String>] {
        state.withLock { $0.observed }
    }

    public var listRequests: [String] {
        state.withLock { $0.listRequests }
    }

    public var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    public func waitForObserved(where predicate: @escaping @Sendable (Set<String>) -> Bool) async {
        await withCheckedContinuation { continuation in
            let satisfied = state.withLock { state -> Bool in
                if let last = state.observed.last, predicate(last) {
                    return true
                }
                state.observeWaiters.append((predicate, continuation))
                return false
            }
            if satisfied {
                continuation.resume()
            }
        }
    }

    private func publish(_ event: SubagentEvent, _ update: (inout State) -> Void) {
        state.withLock { state in
            update(&state)
            for continuation in state.subscribers.values {
                continuation.yield(event)
            }
        }
    }
}
