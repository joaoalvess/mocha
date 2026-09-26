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
        ChatItem(id: id, at: at.addingTimeInterval(interval), kind: kind)
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
