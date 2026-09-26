import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct UsagePaceTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func window(_ kind: UsageWindowKind, used: Double, resetsIn: TimeInterval?) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) })
    }

    @Test func elapsedFractionUsesTheWindowDuration() throws {
        let fiveHour = try #require(UsagePace.elapsedFraction(of: window(.fiveHour, used: 12, resetsIn: 12_930), now: now))
        #expect(abs(fiveHour - 0.281_666) < 0.000_01)
        let weekly = try #require(UsagePace.elapsedFraction(of: window(.weekly, used: 71, resetsIn: 3.5 * 86_400), now: now))
        #expect(abs(weekly - 0.5) < 0.000_01)
    }

    @Test func elapsedFractionIsClampedAndNeedsAResetDate() {
        #expect(UsagePace.elapsedFraction(of: window(.fiveHour, used: 1, resetsIn: -60), now: now) == 1)
        #expect(UsagePace.elapsedFraction(of: window(.fiveHour, used: 1, resetsIn: 30_000), now: now) == 0)
        #expect(UsagePace.elapsedFraction(of: window(.fiveHour, used: 1, resetsIn: nil), now: now) == nil)
        #expect(UsagePace.elapsedFraction(of: window(.unknown, used: 1, resetsIn: 60), now: now) == nil)
    }

    static let trendCases: [(used: Double, elapsed: Double, expected: UsagePaceTrend)] = [
        (12, 0.28, .slower),
        (71, 0.94, .slower),
        (50, 0.5, .onPace),
        (55, 0.5, .onPace),
        (45, 0.5, .onPace),
        (55.1, 0.5, .faster),
        (44.9, 0.5, .slower),
        (80, 0.1, .faster),
    ]

    @Test(arguments: trendCases)
    func trendHasAFivePointTolerance(used: Double, elapsed: Double, expected: UsagePaceTrend) {
        #expect(UsagePace.trend(usedPercent: used, elapsedFraction: elapsed) == expected)
    }

    static let resetCases: [(seconds: TimeInterval, expected: String)] = [
        (12_930, "3h 35m"),
        (210_600, "2d 10h"),
        (86_400, "1d 0h"),
        (3_600, "1h 0m"),
        (3_599, "59m"),
        (30, "0m"),
        (-120, "0m"),
    ]

    @Test(arguments: resetCases)
    func timeUntilResetFormatsDaysHoursAndMinutes(seconds: TimeInterval, expected: String) {
        #expect(UsagePace.timeUntilReset(now.addingTimeInterval(seconds), now: now) == expected)
    }

    @Test func summariesListFiveHourThenWeeklyAndIgnoreUnknown() {
        let snapshot = UsageSnapshot(
            windows: [
                window(.weekly, used: 71, resetsIn: 210_600),
                window(.unknown, used: 3, resetsIn: 60),
                window(.fiveHour, used: 12.4, resetsIn: 12_930),
            ],
            fetchedAt: now
        )
        let summaries = UsagePace.summaries(of: snapshot, now: now)
        #expect(summaries.map(\.label) == ["5h", "7d"])
        #expect(summaries.map(\.percentText) == ["12%", "71%"])
        #expect(summaries.map(\.timeUntilReset) == ["3h 35m", "2d 10h"])
        #expect(summaries.map(\.trend) == [.slower, .faster])
        #expect(abs(summaries[0].usedFraction - 0.124) < 0.000_01)
    }

    @Test func summaryWithoutResetHasNoPaceNorCountdown() {
        let snapshot = UsageSnapshot(windows: [window(.fiveHour, used: 140, resetsIn: nil)], fetchedAt: now)
        let summary = UsagePace.summaries(of: snapshot, now: now)
        #expect(summary.count == 1)
        #expect(summary.first?.elapsedFraction == nil)
        #expect(summary.first?.trend == nil)
        #expect(summary.first?.timeUntilReset == nil)
        #expect(summary.first?.usedFraction == 1)
        #expect(UsagePace.trendLine(summary) == nil)
    }

    @Test func trendLineJoinsBothWindows() {
        let summaries = [
            UsageWindowSummary(kind: .fiveHour, label: "5h", usedPercent: 12, trend: .slower),
            UsageWindowSummary(kind: .weekly, label: "7d", usedPercent: 50, trend: .onPace),
        ]
        #expect(UsagePace.trendLine(summaries) == "5h: ritmo mais lento · 7d: no ritmo")
        #expect(UsagePace.trendLine([UsageWindowSummary(kind: .weekly, label: "7d", usedPercent: 90, trend: .faster)]) == "7d: ritmo mais rápido")
    }

    @Test func accountTitleFallsBackToClaudeAndDropsMissingAccount() {
        #expect(UsagePace.accountTitle(plan: "Max 20x", account: "d•••@e•••.com") == "Max 20x (d•••@e•••.com)")
        #expect(UsagePace.accountTitle(plan: nil, account: "d•••@e•••.com") == "Claude (d•••@e•••.com)")
        #expect(UsagePace.accountTitle(plan: "Pro", account: nil) == "Pro")
        #expect(UsagePace.accountTitle(plan: nil, account: nil) == "Claude")
    }

    @Test func updatedTextUsesRelativeTime() {
        #expect(UsagePace.updatedText(fetchedAt: now.addingTimeInterval(-240), now: now) == "atualizado há 4 min")
        #expect(UsagePace.updatedText(fetchedAt: now.addingTimeInterval(-10), now: now) == "atualizado agora")
    }
}
