import Foundation
import MochaProtocol

public enum AgentsActivityTone: Sendable, Equatable {
    case working
    case waiting
    case done
}

public struct AgentsActivitySummary: Sendable, Equatable {
    public var working: String?
    public var waiting: String?

    public init(working: String?, waiting: String?) {
        self.working = working
        self.waiting = waiting
    }

    public var text: String {
        let parts = [working, waiting].compactMap { $0 }
        return parts.isEmpty ? AgentsActivityText.allDone : parts.joined(separator: AgentsActivityText.separator)
    }
}

public struct AgentsActivityPermissionHeadline: Sendable, Equatable {
    public var toolName: String
    public var verb: String
    public var showsPrompt: Bool

    public init(toolName: String, verb: String, showsPrompt: Bool) {
        self.toolName = toolName
        self.verb = verb
        self.showsPrompt = showsPrompt
    }
}

public enum AgentsActivityText {
    public static let allDone = "Tudo pronto"
    public static let appName = "Mocha"
    public static let staleNote = "sem notícias do Mac"
    public static let open = "Abrir"
    public static let questionHint = "Toque para responder no Mocha"
    public static let permissionFallbackVerb = "quer permissão"
    public static let separator = " · "

    public static func summary(of content: AgentsActivityContent) -> AgentsActivitySummary {
        AgentsActivitySummary(
            working: content.working > 0 ? "\(content.working) trabalhando" : nil,
            waiting: content.waiting > 0 ? "\(content.waiting) esperando você" : nil
        )
    }

    public static func subtitle(isStale: Bool) -> String {
        isStale ? appName + separator + staleNote : appName
    }

    public static func tone(of content: AgentsActivityContent) -> AgentsActivityTone {
        if content.waiting > 0 || content.pending != nil {
            return .waiting
        }
        return content.working > 0 ? .working : .done
    }

    public static func tone(of highlight: AgentsActivityContent.Highlight) -> AgentsActivityTone {
        switch AgentStatus(rawValue: highlight.status) {
        case .blocked: .waiting
        case .working: .working
        default: .done
        }
    }

    public static func highlightDetail(_ highlight: AgentsActivityContent.Highlight) -> String {
        let state = switch tone(of: highlight) {
        case .waiting: "esperando você"
        case .working: "trabalhando"
        case .done: "pronto"
        }
        let label = highlight.workspaceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? state : label + separator + state
    }

    public static func compactCount(of content: AgentsActivityContent) -> String? {
        if content.waiting > 0 {
            return "\(content.waiting)"
        }
        return content.working > 0 ? "\(content.working)" : nil
    }

    public static func deepLink(for content: AgentsActivityContent) -> URL? {
        guard let agentId = content.pending?.agentId ?? content.highlight?.agentId, !agentId.isEmpty else { return nil }
        return DeepLink.agent(agentId).url
    }

    public static func permissionHeadline(toolName: String?) -> AgentsActivityPermissionHeadline {
        let name = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return AgentsActivityPermissionHeadline(toolName: PendingText.unknownAgent, verb: permissionFallbackVerb, showsPrompt: false)
        }
        return AgentsActivityPermissionHeadline(
            toolName: ToolPresentation.displayName(for: name),
            verb: PendingText.verb(forTool: name),
            showsPrompt: ToolPresentation.icon(for: name) == .shell
        )
    }
}
