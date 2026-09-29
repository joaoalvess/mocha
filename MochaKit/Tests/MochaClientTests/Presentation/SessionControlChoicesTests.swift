import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct SessionControlChoicesTests {
    @Test(arguments: [
        ("claude-opus-5-5", ModelAlias.opus),
        ("claude-haiku-4-5-20251001", .haiku),
        ("claude-sonnet-5", .sonnet),
        ("claude-fable-5", .fable),
    ])
    func recognizesModelAlias(model: String, expected: ModelAlias) {
        #expect(SessionControlChoices.alias(of: model) == expected)
    }

    @Test func unknownModelHasNoAlias() {
        #expect(SessionControlChoices.alias(of: "gpt-5-codex") == nil)
        #expect(SessionControlChoices.alias(of: nil) == nil)
    }

    @Test func listsChoicesInOrder() {
        #expect(SessionControlChoices.models.map(\.title) == ["Fable", "Opus", "Sonnet", "Haiku"])
        #expect(SessionControlChoices.efforts.map(\.title) == ["Low", "Medium", "High", "Extra high", "Max"])
        #expect(SessionControlChoices.modes.map(\.title) == ["Edição", "Auto", "Plano"])
    }

    @Test func defaultAndBypassLightNoMode() {
        #expect(SessionControlChoices.mode("default") == nil)
        #expect(SessionControlChoices.mode("bypassPermissions") == nil)
        #expect(SessionControlChoices.mode(nil) == nil)
        #expect(SessionControlChoices.mode("plan") == .plan)
        #expect(SessionControlChoices.mode("acceptEdits") == .acceptEdits)
    }

    @Test func haikuHasNoEffortNorAuto() {
        #expect(!SessionControlChoices.hasEffort(.haiku))
        #expect(SessionControlChoices.hasEffort(.opus))
        #expect(SessionControlChoices.hasEffort(nil))
        #expect(!SessionControlChoices.isAvailable(.auto, on: .haiku))
        #expect(SessionControlChoices.isAvailable(.plan, on: .haiku))
        #expect(SessionControlChoices.isAvailable(.auto, on: .sonnet))
    }

    @Test func parsesEffort() {
        #expect(SessionControlChoices.effort("xhigh") == .xhigh)
        #expect(SessionControlChoices.effort("nope") == nil)
        #expect(SessionControlChoices.effort(nil) == nil)
    }

    @Test func overrideShowsChoiceUntilConfirmedOrReleased() {
        var override = ControlOverride<EffortLevel>()
        #expect(override.displayed(confirmed: .high) == .high)
        override.choose(.low)
        #expect(override.displayed(confirmed: .high) == .low)
        override.release(.max)
        #expect(override.displayed(confirmed: .high) == .low)
        override.release(.low)
        #expect(override.displayed(confirmed: .high) == .high)
        override.choose(.max)
        override.confirmedChanged()
        #expect(override.displayed(confirmed: .max) == .max)
        #expect(override.pending == nil)
    }

    @Test func sendBecomesStopOnlyWhenEmptyAndWorking() {
        #expect(ComposerSendMode.mode(hasContent: false, isWorking: true) == .stop)
        #expect(ComposerSendMode.mode(hasContent: true, isWorking: true) == .send)
        #expect(ComposerSendMode.mode(hasContent: false, isWorking: false) == .send)
    }

    @Test func mergesWorkflowAgentsAfterSubagents() {
        let started = Date(timeIntervalSince1970: 1_000)
        let subagent = SubagentSummary(agentId: "a1", agentType: "general-purpose", description: "Revisar", status: .running)
        let workflow = WorkflowCall(
            toolUseId: "t1",
            name: "revisao",
            status: .running,
            phases: [
                WorkflowPhase(title: "Ler", status: .completed, agents: [WorkflowAgent(agentId: "w1", label: "leitor", status: .completed, durationMs: 4_000)]),
                WorkflowPhase(title: "Revisar", status: .running, agents: [
                    WorkflowAgent(agentId: "w2", label: "revisor", status: .running),
                    WorkflowAgent(agentId: "a1", label: "repetido", status: .running),
                ]),
            ],
            startedAt: started
        )
        let items = [ChatItem(id: "i1", at: started, kind: .workflow(workflow))]

        let merged = SessionAgentsList.merged(subagents: [subagent], chatItems: items)

        #expect(merged.map(\.agentId) == ["a1", "w1", "w2"])
        #expect(merged[1].agentType == "revisao")
        #expect(merged[1].description == "leitor")
        #expect(merged[1].durationMs == 4_000)
        #expect(merged[1].startedAt == nil)
        #expect(merged[2].startedAt == started)
    }

    @Test func modelWithEffort() {
        #expect(ModelName.withEffort("claude-opus-5-5", effort: "xhigh") == "opus-5-5 · xhigh")
        #expect(ModelName.withEffort("claude-haiku-4-5-20251001", effort: nil) == "haiku-4-5")
    }
}
