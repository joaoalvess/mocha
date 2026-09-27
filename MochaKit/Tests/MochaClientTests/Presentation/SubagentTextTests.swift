import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct SubagentTextTests {
    @Test(arguments: [
        (48, "48s"),
        (134, "2m 14s"),
        (62, "1m 02s"),
        (60, "1m 00s"),
        (3_900, "1h 05m"),
        (-3, "0s"),
    ])
    func durationFollowsTheStatusLineFormat(seconds: Int, expected: String) {
        #expect(SubagentText.duration(seconds: seconds) == expected)
    }

    @Test func toolAndAgentCountsUseTheSingular() {
        #expect(SubagentText.toolUses(1) == "1 ferramenta")
        #expect(SubagentText.toolUses(9) == "9 ferramentas")
        #expect(SubagentText.agents(1) == "1 agente")
        #expect(SubagentText.agents(0) == "0 agentes")
    }

    @Test func runningCountsFromStartAndFinishedUsesTheDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(231)
        #expect(SubagentText.elapsed(status: .running, startedAt: start, durationMs: nil, now: now) == "3m 51s")
        #expect(SubagentText.elapsed(status: .completed, startedAt: start, durationMs: 48_000, now: now) == "48s")
        #expect(SubagentText.elapsed(status: .failed, startedAt: nil, durationMs: nil, now: now) == nil)
    }

    @Test func statsLineStartsWithTheFailureOrStopPrefix() {
        #expect(SubagentText.statusPrefix(.failed) == "falhou")
        #expect(SubagentText.statusPrefix(.stopped) == "parado")
        #expect(SubagentText.statusPrefix(.completed) == nil)
        #expect(SubagentText.statsLine(elapsed: "3m 51s", toolUses: 9) == "3m 51s • 9 ferramentas")
        #expect(SubagentText.statsLine(elapsed: nil, toolUses: 1) == "1 ferramenta")
    }

    @Test func topNoticeDropsMissingFields() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let start = Date(timeIntervalSince1970: 13 * 3_600 + 52 * 60)
        #expect(SubagentText.topNotice(agentType: "general-purpose", startedAt: start, model: "claude-opus-5-5", timeZone: utc) == "general-purpose · 13:52 · opus-5-5")
        #expect(SubagentText.topNotice(agentType: "Explore", startedAt: nil, model: nil, timeZone: utc) == "Explore")
    }

    @Test func completedFooterAndStatePill() {
        #expect(SubagentText.completedFooter(durationMs: 134_000, toolUses: 18) == "Concluído em 2m 14s · 18 ferramentas")
        #expect(SubagentText.statePill(.running) == "Rodando · só leitura")
        #expect(SubagentText.statePill(.stopped) == "Parado · só leitura")
        #expect(SubagentText.parentSubtitle("Paginação") == "subagente de Paginação")
    }

    @Test func failureNoticeIsNotRepeatedAfterTheSameNotice() {
        let info = SubagentChatInfo(parentTitle: "p", agentType: "Plan", status: .failed, failureReason: "API Error: 529 Overloaded")
        let same = ChatItem(id: "n", at: Date(), kind: .notice(text: "API Error: 529 Overloaded"))
        let other = ChatItem(id: "m", at: Date(), kind: .assistantText(markdown: "ok"))
        #expect(SubagentText.failureNotice(info, lastItem: same) == nil)
        #expect(SubagentText.failureNotice(info, lastItem: other) == "API Error: 529 Overloaded")
        #expect(SubagentText.failureNotice(SubagentChatInfo(parentTitle: "p", agentType: "Plan", status: .completed), lastItem: other) == nil)
    }

    @Test func phaseCountsFollowThePhaseState() {
        let agents = [
            WorkflowAgent(agentId: "a1", label: "Ajustes", status: .running),
            WorkflowAgent(agentId: "a2", label: "Perfil", status: .running),
            WorkflowAgent(agentId: "a3", label: "Login", status: .completed),
            WorkflowAgent(agentId: "a4", label: "Home", status: .completed),
        ]
        #expect(SubagentText.phaseCount(WorkflowPhase(title: "Corrigir", status: .running, agents: agents)) == "2 de 4 agentes")
        #expect(SubagentText.phaseCount(WorkflowPhase(title: "Mapear", status: .completed, agents: [agents[2]])) == "1 agente")
        #expect(SubagentText.phaseCount(WorkflowPhase(title: "Revisar", status: .pending)) == "pendente")
        #expect(SubagentText.workflowCollapsed(name: "auditoria-a11y", agentCount: 10) == "auditoria-a11y · 10 agentes")
        #expect(SubagentText.workflowFooter(elapsed: "6m 12s", agentCount: 5, toolUses: 86) == "6m 12s • 5 agentes • 86 ferramentas")
    }
}
