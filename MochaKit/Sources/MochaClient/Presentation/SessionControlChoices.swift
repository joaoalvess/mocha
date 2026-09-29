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

    public static let autoUnavailableNote = "Indisponível no Haiku"

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
