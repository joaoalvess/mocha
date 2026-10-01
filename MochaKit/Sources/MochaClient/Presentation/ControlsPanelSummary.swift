import Foundation
import MochaProtocol

public struct ControlsPanelSummary: Sendable, Hashable {
    public var contextText: String?
    public var modeText: String
    public var usageText: String?
    public var subagentsText: String?

    public init(
        contextLeftPercent: Int?,
        contextUsedTokens: Int? = nil,
        mode: PermissionModeTarget?,
        provider: AgentProvider = .claude,
        usage: [UsageWindowSummary],
        subagents: [SubagentSummary]
    ) {
        contextText = contextLeftPercent.map { Self.contextText(leftPercent: $0, usedTokens: contextUsedTokens) }
        modeText = Self.modeText(mode, provider: provider)
        usageText = Self.tightestWindow(usage)?.percentText
        subagentsText = Self.subagentsText(subagents)
    }

    public static let manualModeText = "Manual"
    public static let codexDefaultModeText = "Padrão"

    public static func contextUsedPercent(leftPercent: Int) -> Int {
        100 - min(max(leftPercent, 0), 100)
    }

    public static func contextText(leftPercent: Int, usedTokens: Int?) -> String {
        let percent = "\(contextUsedPercent(leftPercent: leftPercent))%"
        guard let usedTokens, usedTokens > 0 else { return percent }
        return "\(percent) (\(tokenText(usedTokens)))"
    }

    public static func tokenText(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = (Double(tokens) / 100_000).rounded() / 10
            return millions == millions.rounded() ? "\(Int(millions))M" : "\(millions)M"
        }
        if tokens >= 1_000 {
            return "\(Int((Double(tokens) / 1_000).rounded()))k"
        }
        return "\(tokens)"
    }

    public static func modeText(_ mode: PermissionModeTarget?, provider: AgentProvider = .claude) -> String {
        let fallback = provider == .codex ? codexDefaultModeText : manualModeText
        return SessionControlChoices.modes(for: provider).first { $0.mode == mode }?.title ?? fallback
    }

    public static func tightestWindow(_ windows: [UsageWindowSummary]) -> UsageWindowSummary? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }

    public static func subagentsText(_ items: [SubagentSummary]) -> String? {
        guard !items.isEmpty else { return nil }
        let running = items.filter { $0.status == .running }.count
        if running > 0 {
            return "\(running) rodando"
        }
        return "\(items.count)"
    }

    public static func usageTitle(_ window: UsageWindowSummary) -> String {
        switch window.kind {
        case .fiveHour: "5 horas"
        case .weekly: "Semana"
        case .unknown: window.label
        }
    }

    public static func resetText(_ window: UsageWindowSummary) -> String? {
        window.timeUntilReset.map { "renova em \($0)" }
    }

    public static func subagentDetail(_ item: SubagentSummary, now: Date) -> String {
        guard item.status != .running else {
            return [item.agentType, "rodando"].joined(separator: " · ")
        }
        let elapsed = SubagentText.elapsed(status: item.status, startedAt: item.startedAt, durationMs: item.durationMs, now: now)
        return [item.agentType, SubagentText.statusPrefix(item.status), elapsed].compactMap { $0 }.joined(separator: " · ")
    }
}
