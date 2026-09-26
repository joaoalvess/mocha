import Foundation
import MochaProtocol

extension SessionHub {
    func startSessionServices() async {
        archivedSessions = await archive.sessions
        usageSnapshot = await usage.snapshot
        let archiveEvents = archive.events()
        let usageEvents = usage.events()
        sessionServiceTasks = [
            Task { [weak self] in
                for await sessions in archiveEvents {
                    await self?.archivedChanged(sessions)
                }
            },
            Task { [weak self] in
                for await snapshot in usageEvents {
                    await self?.usageChanged(snapshot)
                }
            },
        ]
    }

    func archiveSession(_ sessionId: String, id: String, clientId: UUID) async {
        guard TreeComposer.agents(in: baseTree).contains(where: { $0.sessionId == sessionId }) else {
            send(.sessionNotCurrent, id: id, to: clientId)
            return
        }
        await archive.archive(sessionId: sessionId, at: clock.now())
        send(.ack(), id: id, to: clientId)
        scheduleTreeFlush()
    }

    func archivedWorkspaceLabel(forSession sessionId: String?) -> String {
        guard let sessionId else { return "" }
        return archivedSessions.first { $0.id == sessionId }?.workspaceLabel ?? ""
    }

    func trackSessions() async {
        guard herdrAvailable, !isShuttingDown else { return }
        let agents = TreeComposer.agents(in: baseTree).filter { $0.kind == TreeComposer.claudeKind }
        var current: [String: AgentSummary] = [:]
        for agent in agents {
            if let sessionId = agent.sessionId {
                current[sessionId] = agent
            }
        }
        let previous = trackedSessions
        trackedSessions = current
        let now = clock.now()
        for (sessionId, agent) in previous.sorted(by: { $0.key < $1.key }) where current[sessionId] == nil {
            let replaced = agents.contains { $0.id == agent.id && $0.sessionId != nil }
            let record = ArchivedSession(
                summary: composedSummary(agent),
                sessionId: sessionId,
                reason: replaced ? .cleared : .ended,
                endedAt: now
            )
            await archive.sessionEnded(record)
        }
        await resumeArchivedSessions()
    }

    func refreshSessionState() async {
        let sessionIds = Set(TreeComposer.agents(in: baseTree).compactMap(\.sessionId))
        var contexts: [String: Double] = [:]
        var archived: [String: Date] = [:]
        for sessionId in sessionIds.sorted() {
            if let started = metas[sessionId]?.turnStartedAt, reportedTurnStarts[sessionId] != started {
                reportedTurnStarts[sessionId] = started
                await archive.turnStarted(sessionId: sessionId, at: started)
            }
            archived[sessionId] = await archive.archivedAt(sessionId: sessionId)
            contexts[sessionId] = await usage.contextUsedPercent(forSession: sessionId)
        }
        pluginContexts = contexts
        archivedAts = archived
        reportedTurnStarts = reportedTurnStarts.filter { sessionIds.contains($0.key) }
    }

    private func archivedChanged(_ sessions: [ArchivedSession]) async {
        guard sessions != archivedSessions else { return }
        archivedSessions = sessions
        broadcast(.archived(sessions: sessions))
        refreshChatMetas()
        await resumeArchivedSessions()
    }

    private func usageChanged(_ snapshot: UsageSnapshot?) async {
        if snapshot != usageSnapshot {
            usageSnapshot = snapshot
            if let snapshot {
                broadcast(.usage(snapshot))
            }
        }
        let sessionIds = Set(TreeComposer.agents(in: baseTree).compactMap(\.sessionId))
        var contexts: [String: Double] = [:]
        for sessionId in sessionIds.sorted() {
            contexts[sessionId] = await usage.contextUsedPercent(forSession: sessionId)
        }
        guard contexts != pluginContexts else { return }
        pluginContexts = contexts
        scheduleTreeFlush()
    }

    private func resumeArchivedSessions() async {
        guard herdrAvailable else { return }
        let resumed = archivedSessions.map(\.id).filter { trackedSessions[$0] != nil }
        for sessionId in resumed {
            await archive.sessionResumed(sessionId: sessionId)
        }
    }
}
