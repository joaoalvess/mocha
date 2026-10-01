import Foundation
import MochaProtocol

public enum SubagentText {
    public static let loadFailure = "Não foi possível carregar os subagentes"

    public static func duration(milliseconds: Int) -> String {
        duration(seconds: milliseconds / 1_000)
    }

    public static func duration(from start: Date, to end: Date) -> String {
        duration(seconds: Int(end.timeIntervalSince(start).rounded(.down)))
    }

    public static func duration(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600
        let minutes = total % 3_600 / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return "\(hours)h " + twoDigits(minutes) + "m"
        }
        if minutes > 0 {
            return "\(minutes)m " + twoDigits(remainingSeconds) + "s"
        }
        return "\(remainingSeconds)s"
    }

    public static func toolUses(_ count: Int) -> String {
        count == 1 ? "1 ferramenta" : "\(count) ferramentas"
    }

    public static func agents(_ count: Int) -> String {
        count == 1 ? "1 agente" : "\(count) agentes"
    }

    public static func elapsed(status: SubagentStatus, startedAt: Date?, durationMs: Int?, now: Date) -> String? {
        if status == .running, let startedAt {
            return duration(from: startedAt, to: now)
        }
        if let durationMs {
            return duration(milliseconds: durationMs)
        }
        return startedAt.map { duration(from: $0, to: now) }
    }

    public static func statusPrefix(_ status: SubagentStatus) -> String? {
        switch status {
        case .failed: "falhou"
        case .stopped: "parado"
        case .running, .completed: nil
        }
    }

    public static func statsLine(elapsed: String?, toolUses count: Int) -> String {
        [elapsed, toolUses(count)].compactMap { $0 }.joined(separator: " • ")
    }

    public static func topNotice(agentType: String?, startedAt: Date?, model: String?, timeZone: TimeZone = .current) -> String {
        let time = startedAt.map { clockTime($0, timeZone: timeZone) }
        return [agentType, time, model.map(ModelName.abbreviated)].compactMap { $0 }.joined(separator: " · ")
    }

    public static func parentSubtitle(_ parentTitle: String) -> String {
        "subagente de " + parentTitle
    }

    public static func completedFooter(durationMs: Int?, toolUses count: Int) -> String {
        let elapsed = durationMs.map { "Concluído em " + duration(milliseconds: $0) } ?? "Concluído"
        return elapsed + " · " + toolUses(count)
    }

    public static func failureNotice(_ info: SubagentChatInfo?, lastItem: ChatItem?) -> String? {
        guard let info, info.status == .failed, let reason = info.failureReason, !reason.isEmpty else { return nil }
        if case .notice(let text)? = lastItem?.kind, text == reason {
            return nil
        }
        return reason
    }

    public static func statePill(_ status: SubagentStatus) -> String {
        switch status {
        case .running: "Rodando · só leitura"
        case .completed: "Concluído · só leitura"
        case .failed: "Falhou · só leitura"
        case .stopped: "Parado · só leitura"
        }
    }

    public static func phaseCount(_ phase: WorkflowPhase) -> String {
        switch phase.status {
        case .pending:
            return "pendente"
        case .running:
            let done = phase.agents.filter { $0.status == .completed }.count
            return "\(done) de " + agents(phase.agents.count)
        case .completed, .failed:
            return agents(phase.agents.count)
        }
    }

    public static func workflowCollapsed(name: String, agentCount: Int) -> String {
        name + " · " + agents(agentCount)
    }

    public static func workflowFooter(elapsed: String?, agentCount: Int, toolUses count: Int) -> String {
        [elapsed, agents(agentCount), toolUses(count)].compactMap { $0 }.joined(separator: " • ")
    }

    public static func workflowElapsed(_ call: WorkflowCall, now: Date) -> String? {
        if call.status == .running, let startedAt = call.startedAt {
            return duration(from: startedAt, to: now)
        }
        if let durationMs = call.durationMs {
            return duration(milliseconds: durationMs)
        }
        return call.startedAt.map { duration(from: $0, to: now) }
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func clockTime(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return twoDigits(parts.hour ?? 0) + ":" + twoDigits(parts.minute ?? 0)
    }
}
