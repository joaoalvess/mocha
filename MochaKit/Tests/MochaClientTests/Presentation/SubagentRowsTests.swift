import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct SubagentRowsTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)
    private let sessionId = "s-receitas"

    private var items: [SubagentSummary] {
        [
            SubagentSummary(agentId: "a-load", agentType: "general-purpose", description: "Teste de carga /receitas", status: .running, toolUses: 9, startedAt: now.addingTimeInterval(-231)),
            SubagentSummary(agentId: "a-script", parentAgentId: "a-load", agentType: "Explore", description: "Achar o script de carga", status: .completed, toolUses: 5, durationMs: 41_000),
            SubagentSummary(agentId: "a-index", agentType: "Plan", description: "Revisar o índice de receitas", status: .failed, toolUses: 3, durationMs: 48_000),
            SubagentSummary(agentId: "a-explain", agentType: "Explore", description: "Medir a consulta com EXPLAIN", status: .stopped, toolUses: 1, durationMs: 62_000),
        ]
    }

    @Test func rowsKeepTheDaemonOrderAndIndentTheNested() {
        let rows = SubagentRows.make(items: items, sessionId: sessionId, now: now)
        #expect(rows.map(\.agentId) == ["a-load", "a-script", "a-index", "a-explain"])
        #expect(rows.map(\.isNested) == [false, true, false, false])
    }

    @Test func eachLineShowsTypeTimeAndTools() {
        let rows = SubagentRows.make(items: items, sessionId: sessionId, now: now)
        #expect(rows.map(\.title) == ["Teste de carga /receitas", "Achar o script de carga", "Revisar o índice de receitas", "Medir a consulta com EXPLAIN"])
        #expect(rows.map(\.subtitle) == [
            "general-purpose · 3m 51s · 9 ferramentas",
            "Explore · 41s · 5 ferramentas",
            "Plan · falhou · 48s · 3 ferramentas",
            "Explore · parado · 1m 02s · 1 ferramenta",
        ])
        #expect(rows[2].statusPrefix == "falhou")
    }

    @Test func runningTimeCountsFromTheStart() {
        let later = SubagentRows.row(for: items[0], sessionId: sessionId, now: now.addingTimeInterval(10))
        #expect(later.stats == "4m 01s · 9 ferramentas")
    }

    @Test func everyRowOpensTheSubagentTranscript() {
        let rows = SubagentRows.make(items: items, sessionId: sessionId, now: now)
        #expect(rows[0].target == .subagent(sessionId: sessionId, agentId: "a-load"))
        #expect(rows[1].target == .subagent(sessionId: sessionId, agentId: "a-script"))
    }

    @Test func codexRowsOpenTheChildThread() {
        let child = SubagentSummary(agentId: "9f5e4d3c-6a7b-4c8d-9e0f-2a3b4c5d6e7f", agentType: "explorer", description: "Revisar migrations de índice", status: .running, toolUses: 2, startedAt: now.addingTimeInterval(-140))
        let rows = SubagentRows.make(items: [child], sessionId: "8e4d3c2b-5f6a-4b7c-8d9e-1f2a3b4c5d6e", provider: .codex, now: now)
        #expect(rows.map(\.target) == [.codexThread("9f5e4d3c-6a7b-4c8d-9e0f-2a3b4c5d6e7f")])
        #expect(SubagentRoute.target(agentId: "a-load", sessionId: sessionId, provider: .claude) == .subagent(sessionId: sessionId, agentId: "a-load"))
    }

    @Test func runningCountOnlyWhenSomethingRuns() {
        #expect(SubagentRows.runningCount(items) == "1 rodando")
        #expect(SubagentRows.runningCount(Array(items.dropFirst())) == nil)
    }
}
