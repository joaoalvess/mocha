import Foundation
import MochaProtocol

struct CodexPaneMatcher: Sendable {
    struct Expected: Sendable, Equatable {
        let paneId: AgentID
        let cwd: String
        let since: Date
    }

    struct Started: Sendable, Equatable {
        let threadId: String
        let cwd: String
        let at: Date
    }

    static let window: TimeInterval = 120

    private(set) var expected: [Expected] = []
    private(set) var started: [Started] = []

    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    mutating func expect(_ paneId: AgentID, cwd: String, since: Date, now: Date) -> String? {
        prune(now: now)
        let cwd = Self.normalized(cwd)
        expected.removeAll { $0.paneId == paneId }
        if let index = started.firstIndex(where: { $0.cwd == cwd && $0.at >= since }) {
            return started.remove(at: index).threadId
        }
        expected.append(Expected(paneId: paneId, cwd: cwd, since: since))
        return nil
    }

    mutating func threadStarted(_ threadId: String, cwd: String, at: Date) -> AgentID? {
        prune(now: at)
        let cwd = Self.normalized(cwd)
        if let index = expected.firstIndex(where: { $0.cwd == cwd && $0.since <= at }) {
            return expected.remove(at: index).paneId
        }
        started.append(Started(threadId: threadId, cwd: cwd, at: at))
        return nil
    }

    mutating func forget(_ paneId: AgentID) {
        expected.removeAll { $0.paneId == paneId }
    }

    mutating func move(from oldId: AgentID, to newId: AgentID) {
        expected = expected.map { $0.paneId == oldId ? Expected(paneId: newId, cwd: $0.cwd, since: $0.since) : $0 }
    }

    mutating func reset() {
        expected.removeAll()
        started.removeAll()
    }

    private mutating func prune(now: Date) {
        let limit = now.addingTimeInterval(-Self.window)
        expected.removeAll { $0.since < limit }
        started.removeAll { $0.at < limit }
    }
}
