import Foundation
import MochaProtocol

public struct ControlsPanelSummary: Sendable, Hashable {
    public var contextText: String?
    public var modeText: String
    public var usageText: String?
    public var subagentsText: String?

    public init(contextLeftPercent: Int?, mode: PermissionModeTarget?, usage: [UsageWindowSummary], subagents: [SubagentSummary]) {
        contextText = contextLeftPercent.map(Self.contextText(percent:))
        modeText = Self.modeText(mode)
        usageText = Self.tightestWindow(usage)?.percentText
        subagentsText = Self.subagentsText(subagents)
    }

    public static let manualModeText = "Manual"

    public static func contextText(percent: Int) -> String {
        "\(min(max(percent, 0), 100))% livre"
    }

    public static func modeText(_ mode: PermissionModeTarget?) -> String {
        SessionControlChoices.modes.first { $0.mode == mode }?.title ?? manualModeText
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
        return items.count == 1 ? "1 concluído" : "\(items.count) concluídos"
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
