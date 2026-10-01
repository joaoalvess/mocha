import Foundation
import MochaProtocol

public struct SubagentRow: Sendable, Hashable, Identifiable {
    public var agentId: String
    public var target: ChatTarget
    public var title: String
    public var agentType: String
    public var status: SubagentStatus
    public var isNested: Bool
    public var statusPrefix: String?
    public var stats: String

    public var id: String { agentId }

    public var subtitle: String {
        [agentType, statusPrefix, stats].compactMap { $0 }.joined(separator: " · ")
    }
}

public enum SubagentRoute {
    public static func target(agentId: String, sessionId: String, provider: AgentProvider) -> ChatTarget {
        switch provider {
        case .claude: .subagent(sessionId: sessionId, agentId: agentId)
        case .codex: .codexThread(agentId)
        }
    }
}

public enum SubagentRows {
    public static func make(items: [SubagentSummary], sessionId: String, provider: AgentProvider = .claude, now: Date) -> [SubagentRow] {
        items.map { row(for: $0, sessionId: sessionId, provider: provider, now: now) }
    }

    public static func row(for item: SubagentSummary, sessionId: String, provider: AgentProvider = .claude, now: Date) -> SubagentRow {
        let elapsed = SubagentText.elapsed(status: item.status, startedAt: item.startedAt, durationMs: item.durationMs, now: now)
        return SubagentRow(
            agentId: item.agentId,
            target: SubagentRoute.target(agentId: item.agentId, sessionId: sessionId, provider: provider),
            title: item.description,
            agentType: item.agentType,
            status: item.status,
            isNested: item.parentAgentId != nil,
            statusPrefix: SubagentText.statusPrefix(item.status),
            stats: [elapsed, SubagentText.toolUses(item.toolUses)].compactMap { $0 }.joined(separator: " · ")
        )
    }

    public static func runningCount(_ items: [SubagentSummary]) -> String? {
        let running = items.filter { $0.status == .running }.count
        return running > 0 ? "\(running) rodando" : nil
    }

    public static func hasRunning(_ items: [SubagentSummary]) -> Bool {
        items.contains { $0.status == .running }
    }
}
