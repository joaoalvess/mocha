import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct ControlsPanelSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func subagent(_ id: String, _ status: SubagentStatus, startedAt: Date? = nil, durationMs: Int? = nil) -> SubagentSummary {
        SubagentSummary(agentId: id, agentType: "Explore", description: "Mapear \(id)", status: status, startedAt: startedAt, durationMs: durationMs)
    }

    @Test(arguments: [
        (PermissionModeTarget?.some(.acceptEdits), "Edição"),
        (.some(.auto), "Auto"),
        (.some(.plan), "Plano"),
        (.some(.default), "Manual"),
        (nil, "Manual"),
    ])
    func labelsTheMode(mode: PermissionModeTarget?, expected: String) {
        #expect(ControlsPanelSummary.modeText(mode) == expected)
    }

    @Test func modeChoicesHaveShortDetails() {
        #expect(SessionControlChoices.modes.map(\.detail) == ["aceita edições", "decide sozinho", "planeja antes"])
    }

    @Test func usageShowsTheTightestWindow() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(kind: .fiveHour, usedPercent: 12.4, resetsAt: now.addingTimeInterval(7_800)),
                UsageWindow(kind: .weekly, usedPercent: 26.2, resetsAt: now.addingTimeInterval(3 * 86_400)),
            ],
            fetchedAt: now
        )
        let summary = ControlsPanelSummary(contextLeftPercent: 72, mode: .auto, usage: UsagePace.summaries(of: snapshot, now: now), subagents: [])
        #expect(summary.usageText == "26%")
        #expect(summary.contextText == "72% livre")
        #expect(summary.modeText == "Auto")
    }

    @Test func rowsHideWithoutData() {
        let summary = ControlsPanelSummary(contextLeftPercent: nil, mode: nil, usage: [], subagents: [])
        #expect(summary.contextText == nil)
        #expect(summary.usageText == nil)
        #expect(summary.subagentsText == nil)
        #expect(summary.modeText == "Manual")
    }

    @Test func subagentsCountRunningFirst() {
        #expect(ControlsPanelSummary.subagentsText([subagent("a", .running), subagent("b", .running), subagent("c", .completed)]) == "2 rodando")
        #expect(ControlsPanelSummary.subagentsText([subagent("a", .completed), subagent("b", .failed)]) == "2 concluídos")
        #expect(ControlsPanelSummary.subagentsText([subagent("a", .completed)]) == "1 concluído")
        #expect(ControlsPanelSummary.subagentsText([]) == nil)
    }

    @Test func usageWindowsHaveReadableTitlesAndReset() {
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(kind: .weekly, usedPercent: 40, resetsAt: now.addingTimeInterval(2 * 86_400 + 3_600)),
                UsageWindow(kind: .fiveHour, usedPercent: 10, resetsAt: now.addingTimeInterval(4_980)),
            ],
            fetchedAt: now
        )
        let windows = UsagePace.summaries(of: snapshot, now: now)
        #expect(windows.map(ControlsPanelSummary.usageTitle) == ["5 horas", "Semana"])
        #expect(windows.map(ControlsPanelSummary.resetText) == ["renova em 1h 23m", "renova em 2d 1h"])
    }

    @Test func subagentDetailShowsTypeAndDurationOrRunning() {
        #expect(ControlsPanelSummary.subagentDetail(subagent("a", .running, startedAt: now.addingTimeInterval(-90)), now: now) == "Explore · rodando")
        #expect(ControlsPanelSummary.subagentDetail(subagent("b", .completed, durationMs: 83_000), now: now) == "Explore · 1m 23s")
        #expect(ControlsPanelSummary.subagentDetail(subagent("c", .failed, durationMs: 12_000), now: now) == "Explore · falhou · 12s")
    }

    @Test func contextTextIsClamped() {
        #expect(ControlsPanelSummary.contextText(percent: 140) == "100% livre")
        #expect(ControlsPanelSummary.contextText(percent: -3) == "0% livre")
    }
}
