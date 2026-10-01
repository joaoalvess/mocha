import Foundation
import MochaProtocol

public struct ModelChoice: Sendable, Hashable, Identifiable {
    public var alias: ModelAlias
    public var title: String
    public var detail: String

    public var id: ModelAlias { alias }
}

public struct EffortChoice: Sendable, Hashable, Identifiable {
    public var level: EffortLevel
    public var title: String

    public var id: EffortLevel { level }
}

public struct ModeChoice: Sendable, Hashable, Identifiable {
    public var mode: PermissionModeTarget
    public var title: String
    public var detail: String

    public var id: PermissionModeTarget { mode }
}

public struct PickerOption: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?

    public init(id: String, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct ModelPickerContent: Sendable, Hashable {
    public var models: [PickerOption]
    public var efforts: [PickerOption]
    public var selectedModel: String?
    public var selectedEffort: String?

    public init(models: [PickerOption], efforts: [PickerOption], selectedModel: String?, selectedEffort: String?) {
        self.models = models
        self.efforts = efforts
        self.selectedModel = selectedModel
        self.selectedEffort = selectedEffort
    }
}

public enum SessionControlChoices {
    public static let models: [ModelChoice] = [
        ModelChoice(alias: .fable, title: "Fable", detail: "O mais capaz, para tarefas longas e difíceis"),
        ModelChoice(alias: .opus, title: "Opus", detail: "O melhor para tarefas complexas"),
        ModelChoice(alias: .sonnet, title: "Sonnet", detail: "Eficiente para tarefas de rotina"),
        ModelChoice(alias: .haiku, title: "Haiku", detail: "O mais rápido, para respostas curtas"),
    ]

    public static let efforts: [EffortChoice] = [
        EffortChoice(level: .low, title: "Low"),
        EffortChoice(level: .medium, title: "Medium"),
        EffortChoice(level: .high, title: "High"),
        EffortChoice(level: .xhigh, title: "Extra high"),
        EffortChoice(level: .max, title: "Max"),
    ]

    public static let modes: [ModeChoice] = [
        ModeChoice(mode: .acceptEdits, title: "Edição", detail: "aceita edições"),
        ModeChoice(mode: .auto, title: "Auto", detail: "decide sozinho"),
        ModeChoice(mode: .plan, title: "Plano", detail: "planeja antes"),
    ]

    public static let codexModes: [ModeChoice] = [
        ModeChoice(mode: .default, title: "Padrão", detail: "executa o pedido"),
        ModeChoice(mode: .plan, title: "Plano", detail: "planeja antes"),
    ]

    public static let autoUnavailableNote = "Indisponível no Haiku"
    public static let codexDefaultModelNote = "padrão do Codex"
    public static let modelsLoading = "Carregando modelos…"
    public static let modelsLoadFailure = "Não foi possível carregar os modelos"

    public static func modes(for provider: AgentProvider) -> [ModeChoice] {
        provider == .codex ? codexModes : modes
    }

    public static func mode(_ permissionMode: String?, provider: AgentProvider) -> PermissionModeTarget? {
        guard provider == .codex else { return mode(permissionMode) }
        return permissionMode == PermissionModeTarget.plan.rawValue ? .plan : .default
    }

    public static func confirmedModel(_ model: String?, provider: AgentProvider) -> String? {
        provider == .codex ? model : alias(of: model)?.rawValue
    }

    public static func confirmedEffort(_ effort: String?, provider: AgentProvider) -> String? {
        provider == .codex ? effort : self.effort(effort)?.rawValue
    }

    public static func claudePicker(model: String?, effort: String?) -> ModelPickerContent {
        let alias = model.flatMap(ModelAlias.init(rawValue:))
        return ModelPickerContent(
            models: models.map { PickerOption(id: $0.alias.rawValue, title: $0.title, detail: $0.detail) },
            efforts: hasEffort(alias) ? efforts.map { PickerOption(id: $0.level.rawValue, title: $0.title) } : [],
            selectedModel: alias?.rawValue,
            selectedEffort: effort
        )
    }

    public static func codexPicker(options: [ModelOption], model: String?, effort: String?) -> ModelPickerContent {
        let current = model.flatMap { model in options.first { $0.id.caseInsensitiveCompare(model) == .orderedSame } }
        return ModelPickerContent(
            models: options.map { PickerOption(id: $0.id, title: $0.displayName, detail: $0.isDefault ? codexDefaultModelNote : nil) },
            efforts: (current?.efforts ?? []).map { PickerOption(id: $0.level, title: effortTitle($0.level), detail: $0.description) },
            selectedModel: current?.id ?? model,
            selectedEffort: effort
        )
    }

    public static func headerModel(_ model: String?, effort: String?, provider: AgentProvider) -> String? {
        guard provider == .codex, let model else { return model }
        return [model, effort].compactMap { $0 }.joined(separator: " ")
    }

    public static func effortTitle(_ level: String) -> String {
        if let choice = efforts.first(where: { $0.level.rawValue == level }) {
            return choice.title
        }
        return level.prefix(1).uppercased() + level.dropFirst()
    }

    public static func gaugeLevel(_ effort: String?) -> EffortLevel? {
        guard let effort else { return nil }
        if let level = EffortLevel(rawValue: effort) {
            return level
        }
        switch effort {
        case "ultra": return .max
        case "minimal", "none": return .low
        default: return nil
        }
    }

    public static func alias(of model: String?) -> ModelAlias? {
        guard let model = model?.lowercased() else { return nil }
        return ModelAlias.allCases.first { model.contains($0.rawValue) }
    }

    public static func effort(_ value: String?) -> EffortLevel? {
        value.flatMap(EffortLevel.init(rawValue:))
    }

    public static func mode(_ permissionMode: String?) -> PermissionModeTarget? {
        guard let mode = permissionMode.flatMap(PermissionModeTarget.init(rawValue:)), mode != .default else { return nil }
        return mode
    }

    public static func hasEffort(_ model: ModelAlias?) -> Bool {
        model != .haiku
    }

    public static func isAvailable(_ mode: PermissionModeTarget, on model: ModelAlias?) -> Bool {
        !(mode == .auto && model == .haiku)
    }
}

public enum ModelListState: Sendable, Hashable {
    case idle
    case loading
    case loaded([ModelOption])
    case failed

    public var options: [ModelOption] {
        if case .loaded(let options) = self { options } else { [] }
    }

    public var needsLoad: Bool {
        self == .idle || self == .failed
    }

    public var notice: String? {
        switch self {
        case .loading: SessionControlChoices.modelsLoading
        case .failed: SessionControlChoices.modelsLoadFailure
        case .idle, .loaded: nil
        }
    }
}

public struct ControlOverride<Value: Hashable & Sendable>: Sendable, Hashable {
    public private(set) var pending: Value?

    public init(pending: Value? = nil) {
        self.pending = pending
    }

    public func displayed(confirmed: Value?) -> Value? {
        pending ?? confirmed
    }

    public mutating func choose(_ value: Value) {
        pending = value
    }

    public mutating func confirmedChanged() {
        pending = nil
    }

    public mutating func release(_ value: Value) {
        guard pending == value else { return }
        pending = nil
    }
}

public enum ComposerSendMode: Sendable, Hashable {
    case send
    case stop
    case microphone
    case dictating

    public static func mode(hasContent: Bool, isWorking: Bool, isDictating: Bool = false, canDictate: Bool = false) -> ComposerSendMode {
        if isDictating { return .dictating }
        if hasContent { return .send }
        if isWorking { return .stop }
        return canDictate ? .microphone : .send
    }
}

public enum SessionAgentsList {
    public static func merged(subagents: [SubagentSummary], chatItems: [ChatItem]) -> [SubagentSummary] {
        var seen = Set(subagents.map(\.agentId))
        var workflowAgents: [SubagentSummary] = []
        for item in chatItems {
            guard case .workflow(let workflow) = item.kind else { continue }
            for phase in workflow.phases {
                for agent in phase.agents where !seen.contains(agent.agentId) {
                    seen.insert(agent.agentId)
                    workflowAgents.append(
                        SubagentSummary(
                            agentId: agent.agentId,
                            agentType: workflow.name,
                            description: agent.label,
                            status: agent.status,
                            startedAt: agent.status == .running ? workflow.startedAt : nil,
                            durationMs: agent.durationMs
                        )
                    )
                }
            }
        }
        return subagents + workflowAgents
    }
}

public enum EffortGauge {
    public static let unknownFraction = 0.5

    public static func fraction(for level: EffortLevel?) -> Double {
        guard let level, let index = EffortLevel.allCases.firstIndex(of: level) else { return unknownFraction }
        return Double(index + 1) / Double(EffortLevel.allCases.count)
    }
}
