import Foundation
import MochaProtocol

public enum UsagePaceTrend: Sendable, Hashable {
    case faster
    case onPace
    case slower

    public var text: String {
        switch self {
        case .faster: "ritmo mais rápido"
        case .onPace: "no ritmo"
        case .slower: "ritmo mais lento"
        }
    }
}

public struct UsageWindowSummary: Sendable, Hashable, Identifiable {
    public var id: Int
    public var kind: UsageWindowKind
    public var label: String
    public var usedPercent: Double
    public var elapsedFraction: Double?
    public var trend: UsagePaceTrend?
    public var timeUntilReset: String?

    public var usedFraction: Double {
        min(max(usedPercent / 100, 0), 1)
    }

    public var percentText: String {
        "\(Int(usedPercent.rounded()))%"
    }

    public init(
        id: Int = 0,
        kind: UsageWindowKind,
        label: String,
        usedPercent: Double,
        elapsedFraction: Double? = nil,
        trend: UsagePaceTrend? = nil,
        timeUntilReset: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.elapsedFraction = elapsedFraction
        self.trend = trend
        self.timeUntilReset = timeUntilReset
    }
}

public enum UsagePace {
    public static let tolerance = 5.0
    public static let defaultAccountTitle = "Claude"

    private static let minute = 60
    private static let hour = 60 * minute
    private static let day = 24 * hour

    public static func duration(of kind: UsageWindowKind) -> TimeInterval? {
        switch kind {
        case .fiveHour: TimeInterval(5 * hour)
        case .weekly: TimeInterval(7 * day)
        case .unknown: nil
        }
    }

    public static func duration(of window: UsageWindow) -> TimeInterval? {
        if let minutes = window.windowDurationMins, minutes > 0 {
            return TimeInterval(minutes * minute)
        }
        return duration(of: window.kind)
    }

    public static func label(of kind: UsageWindowKind) -> String? {
        switch kind {
        case .fiveHour: "5h"
        case .weekly: "7d"
        case .unknown: nil
        }
    }

    public static func label(of window: UsageWindow) -> String? {
        guard let minutes = window.windowDurationMins, minutes > 0 else { return label(of: window.kind) }
        if minutes % (24 * 60) == 0 { return "\(minutes / (24 * 60))d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    public static func elapsedFraction(of window: UsageWindow, now: Date) -> Double? {
        guard let duration = duration(of: window), let resetsAt = window.resetsAt else { return nil }
        let fraction = 1 - resetsAt.timeIntervalSince(now) / duration
        return min(max(fraction, 0), 1)
    }

    public static func trend(usedPercent: Double, elapsedFraction: Double) -> UsagePaceTrend {
        let pace = usedPercent - elapsedFraction * 100
        if pace > tolerance {
            return .faster
        }
        if pace < -tolerance {
            return .slower
        }
        return .onPace
    }

    public static func timeUntilReset(_ resetsAt: Date, now: Date) -> String {
        let remaining = max(0, Int(resetsAt.timeIntervalSince(now)))
        let days = remaining / day
        let hours = remaining % day / hour
        let minutes = remaining % hour / minute
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func summaries(of snapshot: UsageSnapshot, now: Date) -> [UsageWindowSummary] {
        let valid = snapshot.windows.compactMap { window -> (window: UsageWindow, label: String)? in
            guard let label = label(of: window) else { return nil }
            return (window, label)
        }
        let sorted = valid.sorted { (duration(of: $0.window) ?? .greatestFiniteMagnitude) < (duration(of: $1.window) ?? .greatestFiniteMagnitude) }
        return sorted.enumerated().map { index, entry in
            let window = entry.window
            let elapsed = elapsedFraction(of: window, now: now)
            return UsageWindowSummary(
                id: index,
                kind: window.kind,
                label: entry.label,
                usedPercent: window.usedPercent,
                elapsedFraction: elapsed,
                trend: elapsed.map { trend(usedPercent: window.usedPercent, elapsedFraction: $0) },
                timeUntilReset: window.resetsAt.map { timeUntilReset($0, now: now) }
            )
        }
    }

    public static func trendLine(_ summaries: [UsageWindowSummary]) -> String? {
        let parts = summaries.compactMap { summary in
            summary.trend.map { "\(summary.label): \($0.text)" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func accountTitle(plan: String?, account: String?, provider: AgentProvider = .claude) -> String {
        let name = plan ?? (provider == .codex ? "Codex" : defaultAccountTitle)
        guard let account else { return name }
        return "\(name) (\(account))"
    }

    public static func updatedText(fetchedAt: Date, now: Date) -> String {
        "atualizado " + RelativeTime.text(from: fetchedAt, now: now)
    }
}
