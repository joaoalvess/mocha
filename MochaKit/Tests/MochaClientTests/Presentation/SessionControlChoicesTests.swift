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

    @Test func effortGaugeFillsByLevel() {
        #expect(EffortGauge.fraction(for: .low) == 0.2)
        #expect(EffortGauge.fraction(for: .high) == 0.6)
        #expect(EffortGauge.fraction(for: .max) == 1)
        #expect(EffortGauge.fraction(for: nil) == EffortGauge.unknownFraction)
    }

    @Test func primaryButtonBecomesMicrophoneOnlyWhenEmptyAndIdle() {
        #expect(ComposerSendMode.mode(hasContent: false, isWorking: false, canDictate: true) == .microphone)
        #expect(ComposerSendMode.mode(hasContent: true, isWorking: false, canDictate: true) == .send)
        #expect(ComposerSendMode.mode(hasContent: false, isWorking: true, canDictate: true) == .stop)
        #expect(ComposerSendMode.mode(hasContent: true, isWorking: true, isDictating: true, canDictate: true) == .dictating)
    }

    private var codexModels: [ModelOption] {
        [
            ModelOption(
                id: "gpt-6.1-sol",
                displayName: "GPT-6.1-Sol",
                isDefault: true,
                defaultEffort: "low",
                efforts: [EffortOption(level: "low", description: "Rápido, com pouco raciocínio"), EffortOption(level: "max"), EffortOption(level: "ultra")]
            ),
            ModelOption(id: "gpt-6-luna", displayName: "GPT-6-Luna", defaultEffort: "medium", efforts: [EffortOption(level: "low"), EffortOption(level: "high")]),
        ]
    }

    @Test func codexOffersOnlyDefaultAndPlan() {
        #expect(SessionControlChoices.modes(for: .codex).map(\.title) == ["Padrão", "Plano"])
        #expect(SessionControlChoices.modes(for: .codex).map(\.mode) == [.default, .plan])
        #expect(SessionControlChoices.modes(for: .claude) == SessionControlChoices.modes)
    }

    @Test func codexModeIsPlanOrDefault() {
        #expect(SessionControlChoices.mode("plan", provider: .codex) == .plan)
        #expect(SessionControlChoices.mode("default", provider: .codex) == .default)
        #expect(SessionControlChoices.mode(nil, provider: .codex) == .default)
        #expect(SessionControlChoices.mode("default", provider: .claude) == nil)
        #expect(SessionControlChoices.mode("acceptEdits", provider: .claude) == .acceptEdits)
    }

    @Test func confirmedValuesKeepCodexStringsAndClaudeAliases() {
        #expect(SessionControlChoices.confirmedModel("gpt-6.1-sol", provider: .codex) == "gpt-6.1-sol")
        #expect(SessionControlChoices.confirmedModel("claude-opus-5-5", provider: .claude) == "opus")
        #expect(SessionControlChoices.confirmedEffort("ultra", provider: .codex) == "ultra")
        #expect(SessionControlChoices.confirmedEffort("ultra", provider: .claude) == nil)
        #expect(SessionControlChoices.confirmedEffort("xhigh", provider: .claude) == "xhigh")
    }

    @Test func codexPickerListsEveryModelAndTheEffortsOfTheCurrentOne() {
        let picker = SessionControlChoices.codexPicker(options: codexModels, model: "gpt-6.1-sol", effort: "max")
        #expect(picker.models.map(\.id) == ["gpt-6.1-sol", "gpt-6-luna"])
        #expect(picker.models.map(\.title) == ["GPT-6.1-Sol", "GPT-6-Luna"])
        #expect(picker.models.map(\.detail) == ["padrão do Codex", nil])
        #expect(picker.efforts.map(\.id) == ["low", "max", "ultra"])
        #expect(picker.efforts.map(\.title) == ["Low", "Max", "Ultra"])
        #expect(picker.efforts.first?.detail == "Rápido, com pouco raciocínio")
        #expect(picker.selectedModel == "gpt-6.1-sol")
        #expect(picker.selectedEffort == "max")
    }

    @Test func codexPickerFollowsTheChosenModel() {
        let picker = SessionControlChoices.codexPicker(options: codexModels, model: "GPT-6-Luna", effort: "high")
        #expect(picker.selectedModel == "gpt-6-luna")
        #expect(picker.efforts.map(\.id) == ["low", "high"])
    }

    @Test func codexPickerWithoutTheListOrAnUnknownModelOffersNoEffort() {
        #expect(SessionControlChoices.codexPicker(options: [], model: "gpt-6.1-sol", effort: "low").models.isEmpty)
        let unknown = SessionControlChoices.codexPicker(options: codexModels, model: "gpt-oculto", effort: "low")
        #expect(unknown.efforts.isEmpty)
        #expect(unknown.selectedModel == "gpt-oculto")
    }

    @Test func claudePickerKeepsTheFixedListAndHidesEffortOnHaiku() {
        let opus = SessionControlChoices.claudePicker(model: "opus", effort: "high")
        #expect(opus.models.map(\.title) == ["Fable", "Opus", "Sonnet", "Haiku"])
        #expect(opus.efforts.map(\.title) == ["Low", "Medium", "High", "Extra high", "Max"])
        #expect(opus.selectedModel == "opus")
        #expect(opus.selectedEffort == "high")
        #expect(SessionControlChoices.claudePicker(model: "haiku", effort: nil).efforts.isEmpty)
    }

    @Test func gaugeLevelMapsCodexEfforts() {
        #expect(SessionControlChoices.gaugeLevel("xhigh") == .xhigh)
        #expect(SessionControlChoices.gaugeLevel("ultra") == .max)
        #expect(SessionControlChoices.gaugeLevel("minimal") == .low)
        #expect(SessionControlChoices.gaugeLevel("outro") == nil)
        #expect(SessionControlChoices.gaugeLevel(nil) == nil)
    }

    @Test func headerShowsTheCodexModelWithItsEffort() {
        #expect(SessionControlChoices.headerModel("gpt-6.1-sol", effort: "low", provider: .codex) == "gpt-6.1-sol low")
        #expect(SessionControlChoices.headerModel("gpt-6.1-sol", effort: nil, provider: .codex) == "gpt-6.1-sol")
        #expect(SessionControlChoices.headerModel(nil, effort: "low", provider: .codex) == nil)
        #expect(SessionControlChoices.headerModel("claude-opus-5-5", effort: "high", provider: .claude) == "claude-opus-5-5")
    }

    @Test func modelListStateDrivesThePickerNotice() {
        #expect(ModelListState.idle.needsLoad)
        #expect(ModelListState.failed.needsLoad)
        #expect(!ModelListState.loading.needsLoad)
        #expect(!ModelListState.loaded(codexModels).needsLoad)
        #expect(ModelListState.loading.notice == "Carregando modelos…")
        #expect(ModelListState.failed.notice == "Não foi possível carregar os modelos")
        #expect(ModelListState.loaded(codexModels).notice == nil)
        #expect(ModelListState.loaded(codexModels).options.count == 2)
        #expect(ModelListState.failed.options.isEmpty)
    }

    @Test func overrideHoldsCodexStrings() {
        var override = ControlOverride<String>()
        override.choose("gpt-6-luna")
        #expect(override.displayed(confirmed: "gpt-6.1-sol") == "gpt-6-luna")
        override.release("gpt-6-luna")
        #expect(override.displayed(confirmed: "gpt-6.1-sol") == "gpt-6.1-sol")
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
}
