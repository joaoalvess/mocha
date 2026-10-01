import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct PlanApprovalTests {
    private let start = Date(timeIntervalSince1970: 1_790_337_600)

    private var items: [ChatItem] {
        [
            ChatItem(id: "prompt", at: start, kind: .userPrompt(text: "planeja o cache", imageCount: 0)),
            ChatItem(id: "plan", at: start.addingTimeInterval(60), kind: .assistantText(markdown: "## Plano")),
            ChatItem(id: "footer", at: start.addingTimeInterval(61), kind: .turnFooter(durationMs: 61_000)),
        ]
    }

    private func planItemId(
        provider: AgentProvider = .codex,
        permissionMode: String? = "plan",
        status: AgentStatus = .idle,
        canSend: Bool = true,
        items: [ChatItem]? = nil
    ) -> String? {
        PlanApproval.planItemId(provider: provider, permissionMode: permissionMode, status: status, canSend: canSend, items: items ?? self.items)
    }

    @Test func buttonSitsOnTheLastPlanOfAnIdleCodexInPlan() {
        #expect(planItemId() == "plan")
        #expect(planItemId(status: .done) == "plan")
        #expect(PlanApproval.buttonTitle == "Implementar plano")
        #expect(PlanApproval.prompt == "Implemente o plano.")
    }

    @Test func noButtonDuringATurnOrOutsidePlan() {
        #expect(planItemId(status: .working) == nil)
        #expect(planItemId(status: .blocked) == nil)
        #expect(planItemId(permissionMode: "default") == nil)
        #expect(planItemId(permissionMode: nil) == nil)
    }

    @Test func noButtonForClaudeOrWithoutControl() {
        #expect(planItemId(provider: .claude) == nil)
        #expect(planItemId(canSend: false) == nil)
    }

    @Test func noButtonWhenTheTurnDidNotEndInAPlan() {
        let toolLast = items.dropLast() + [ChatItem(id: "tool", at: start.addingTimeInterval(62), kind: .notice(text: "Interrompido"))]
        #expect(planItemId(items: Array(toolLast)) == nil)
        #expect(planItemId(items: [items[0]]) == nil)
        #expect(planItemId(items: []) == nil)
    }
}
