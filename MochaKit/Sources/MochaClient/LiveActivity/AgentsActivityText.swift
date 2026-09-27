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

public struct AgentsActivityContext: Sendable, Equatable {
    public var leftPercent: Int
    public var isBlocked: Bool

    public init(leftPercent: Int, isBlocked: Bool) {
        self.leftPercent = leftPercent
        self.isBlocked = isBlocked
    }

    public var fraction: Double {
        Double(leftPercent) / 100
    }
}

public struct AgentsActivityHeader: Sendable, Equatable {
    public var label: String
    public var tone: AgentsActivityTone
    public var model: String?
    public var context: AgentsActivityContext?

    public init(label: String, tone: AgentsActivityTone, model: String?, context: AgentsActivityContext?) {
        self.label = label
        self.tone = tone
        self.model = model
        self.context = context
    }
}

public struct AgentsActivityLines: Sendable, Equatable {
    public enum Detail: Sendable, Equatable {
        case continuation
        case command(String)
    }

    public var headline: String
    public var detail: Detail?

    public init(headline: String, detail: Detail?) {
        self.headline = headline
        self.detail = detail
    }
}

public struct AgentsActivityFootnote: Sendable, Equatable {
    public var working: String?
    public var waiting: String?
    public var stale: String?

    public init(working: String?, waiting: String?, stale: String?) {
        self.working = working
        self.waiting = waiting
        self.stale = stale
    }

    public var text: String {
        [working, waiting, stale].compactMap { $0 }.joined(separator: AgentsActivityText.separator)
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
    public static let othersPrefix = "+"
    public static let shellPrompt = "$ "
    public static let activitySeparator = ": "
    public static let singleRowActionLimit = 2

    public static func summary(of content: AgentsActivityContent) -> AgentsActivitySummary {
        counts(working: content.working, waiting: content.waiting)
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

    public static func header(of content: AgentsActivityContent) -> AgentsActivityHeader {
        let highlight = content.highlight
        let tone: AgentsActivityTone = content.pending != nil ? .waiting : highlight.map(tone(of:)) ?? .done
        let label = singleLine(highlight?.tabTitle) ?? singleLine(highlight?.workspaceLabel) ?? appName
        let model = singleLine(highlight?.model).map(ModelName.abbreviated).flatMap(singleLine)
        let context = highlight?.contextLeftPercent.map {
            AgentsActivityContext(leftPercent: min(max($0, 0), 100), isBlocked: tone == .waiting)
        }
        return AgentsActivityHeader(label: label, tone: tone, model: model, context: context)
    }

    public static func lines(of content: AgentsActivityContent) -> AgentsActivityLines {
        if let pending = content.pending {
            return pendingLines(pending)
        }
        guard content.isBusy else {
            return AgentsActivityLines(headline: allDone, detail: nil)
        }
        guard let highlight = content.highlight else {
            return AgentsActivityLines(headline: summary(of: content).text, detail: nil)
        }
        let headline = singleLine(highlight.activity).map(activityText) ?? singleLine(highlight.preview) ?? singleLine(highlight.title)
        return AgentsActivityLines(headline: headline ?? summary(of: content).text, detail: .continuation)
    }

    public static func footnote(of content: AgentsActivityContent, isStale: Bool) -> AgentsActivityFootnote? {
        let others = othersSummary(of: content)
        let stale = isStale ? staleNote : nil
        guard others.working != nil || others.waiting != nil || stale != nil else { return nil }
        return AgentsActivityFootnote(working: others.working, waiting: others.waiting, stale: stale)
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

    private static func pendingLines(_ pending: AgentsActivityContent.Pending) -> AgentsActivityLines {
        switch pending.kind {
        case .permission:
            let headline = permissionHeadline(toolName: pending.toolName)
            let command = singleLine(pending.text).map { headline.showsPrompt ? shellPrompt + $0 : $0 }
            return AgentsActivityLines(headline: headline.toolName + " " + headline.verb, detail: command.map(AgentsActivityLines.Detail.command))
        case .question:
            let hasTwoRowsOfActions = AgentsActivityActions.actions(for: pending).count > singleRowActionLimit
            return AgentsActivityLines(
                headline: singleLine(pending.text) ?? PendingText.questionHeader,
                detail: hasTwoRowsOfActions ? nil : .continuation
            )
        }
    }

    private static func othersSummary(of content: AgentsActivityContent) -> AgentsActivitySummary {
        guard let highlight = content.highlight else { return AgentsActivitySummary(working: nil, waiting: nil) }
        let status = AgentStatus(rawValue: highlight.status)
        let others = counts(
            working: max(0, content.working - (status == .working ? 1 : 0)),
            waiting: max(0, content.waiting - (status == .blocked ? 1 : 0))
        )
        return AgentsActivitySummary(
            working: others.working.map { othersPrefix + $0 },
            waiting: others.waiting.map { others.working == nil ? othersPrefix + $0 : $0 }
        )
    }

    private static func counts(working: Int, waiting: Int) -> AgentsActivitySummary {
        AgentsActivitySummary(
            working: working > 0 ? "\(working) trabalhando" : nil,
            waiting: waiting > 0 ? "\(waiting) esperando você" : nil
        )
    }

    private static func activityText(_ activity: String) -> String {
        guard let separator = activity.range(of: activitySeparator) else {
            return ToolPresentation.displayName(for: activity)
        }
        return ToolPresentation.displayName(for: String(activity[..<separator.lowerBound])) + activity[separator.lowerBound...]
    }

    private static func singleLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
