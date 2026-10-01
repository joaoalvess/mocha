import Foundation
import MochaProtocol

extension Optional where Wrapped == Date {
    func shifted(by interval: TimeInterval) -> Date? {
        map { $0.addingTimeInterval(interval) }
    }
}

extension AgentSummary {
    func shifted(by interval: TimeInterval) -> AgentSummary {
        var agent = self
        agent.lastActivityAt = lastActivityAt.shifted(by: interval)
        agent.sessionStartedAt = sessionStartedAt.shifted(by: interval)
        agent.turnStartedAt = turnStartedAt.shifted(by: interval)
        agent.turnEndedAt = turnEndedAt.shifted(by: interval)
        agent.archivedAt = archivedAt.shifted(by: interval)
        return agent
    }
}

extension WorkspaceNode {
    func shifted(by interval: TimeInterval) -> WorkspaceNode {
        var workspace = self
        workspace.tabs = tabs.map { tab in
            var tab = tab
            tab.agents = tab.agents.map { $0.shifted(by: interval) }
            return tab
        }
        workspace.children = children.map { $0.shifted(by: interval) }
        return workspace
    }
}

extension ChatItem {
    func shifted(by interval: TimeInterval) -> ChatItem {
        var item = self
        item.at = at.addingTimeInterval(interval)
        item.kind = kind.shifted(by: interval)
        return item
    }
}

extension ChatItemKind {
    func shifted(by interval: TimeInterval) -> ChatItemKind {
        switch self {
        case .subagent(var call):
            call.startedAt = call.startedAt.shifted(by: interval)
            return .subagent(call)
        case .workflow(var call):
            call.startedAt = call.startedAt.shifted(by: interval)
            return .workflow(call)
        default:
            return self
        }
    }
}

extension ArchivedSession {
    func shifted(by interval: TimeInterval) -> ArchivedSession {
        var session = self
        session.endedAt = endedAt.addingTimeInterval(interval)
        session.sessionStartedAt = sessionStartedAt.shifted(by: interval)
        session.lastActivityAt = lastActivityAt.shifted(by: interval)
        return session
    }
}

extension UsageSnapshot {
    func shifted(by interval: TimeInterval) -> UsageSnapshot {
        var snapshot = self
        snapshot.fetchedAt = fetchedAt.addingTimeInterval(interval)
        snapshot.windows = windows.map { window in
            var window = window
            window.resetsAt = window.resetsAt.shifted(by: interval)
            return window
        }
        return snapshot
    }
}
