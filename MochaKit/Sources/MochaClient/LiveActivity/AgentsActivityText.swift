import Foundation
import MochaProtocol

public enum AgentsActivityTone: Sendable, Equatable {
    case working
    case waiting
    case done
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
    public var project: String
    public var provider: AgentProvider
    public var tone: AgentsActivityTone
    public var model: String?
    public var context: AgentsActivityContext?

    public init(project: String, provider: AgentProvider = .claude, tone: AgentsActivityTone, model: String?, context: AgentsActivityContext?) {
        self.project = project
        self.provider = provider
        self.tone = tone
        self.model = model
        self.context = context
    }
}

public struct AgentsActivityLines: Sendable, Equatable {
    public enum Detail: Sendable, Equatable {
        case continuation
        case command(String)
        case text(String)
    }

    public var headline: String
    public var detail: Detail?
    public var emphasizesDetail: Bool

    public init(headline: String, detail: Detail?, emphasizesDetail: Bool = false) {
        self.headline = headline
        self.detail = detail
        self.emphasizesDetail = emphasizesDetail
    }
}

public enum AgentsActivityText {
    public static let appName = "Mocha"
    public static let staleNote = "sem notícias do Mac"
    public static let open = "Abrir"
    public static let questionHint = "Toque para responder no Mocha"
    public static let permissionFallbackVerb = "quer permissão"
    public static let separator = " · "
    public static let shellPrompt = "$ "
    public static let activitySeparator = ": "
    public static let promptPrefix = "Você: "
    public static let singleRowActionLimit = 2
    public static let allowedOutcome = "Aprovado"
    public static let deniedOutcome = "Negado"
    public static let answeredOutcome = "Respondido"

    public static func tone(of content: AgentsActivityContent) -> AgentsActivityTone {
        if content.pending != nil {
            return .waiting
        }
        switch AgentStatus(rawValue: content.status) {
        case .blocked: return .waiting
        case .working: return .working
        default: return .done
        }
    }

    public static func header(of content: AgentsActivityContent) -> AgentsActivityHeader {
        let tone: AgentsActivityTone = AgentStatus(rawValue: content.status) == .idle ? .done : .working
        let project = singleLine(content.workspaceLabel) ?? appName
        let model = singleLine(content.model).map(ModelName.abbreviated).flatMap(singleLine)
        let context = content.contextLeftPercent.map {
            AgentsActivityContext(leftPercent: min(max($0, 0), 100), isBlocked: false)
        }
        return AgentsActivityHeader(project: project, provider: content.provider ?? .claude, tone: tone, model: model, context: context)
    }

    public static func lines(of content: AgentsActivityContent) -> AgentsActivityLines {
        if let pending = content.pending {
            return pendingLines(pending)
        }
        let prompt = singleLine(content.prompt).map { AgentsActivityLines.Detail.text(promptPrefix + $0) }
        if let outcome = content.outcome.flatMap(AgentsActivityOutcome.init(rawValue:)) {
            return AgentsActivityLines(headline: outcomeText(outcome), detail: prompt)
        }
        let headline = singleLine(content.preview) ?? singleLine(content.activity).map(activityText) ?? singleLine(content.title)
        return AgentsActivityLines(headline: headline ?? appName, detail: prompt ?? .continuation)
    }

    public static func outcomeText(_ outcome: AgentsActivityOutcome) -> String {
        switch outcome {
        case .allowed: allowedOutcome
        case .denied: deniedOutcome
        case .answered: answeredOutcome
        }
    }

    public static func footnote(isStale: Bool) -> String? {
        isStale ? staleNote : nil
    }

    public static func deepLink(forAgent agentId: String) -> URL? {
        guard !agentId.isEmpty else { return nil }
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
        case .permission where pending.toolName == PendingText.planToolName:
            return AgentsActivityLines(headline: PendingText.planTitle, detail: singleLine(pending.text).map(AgentsActivityLines.Detail.text), emphasizesDetail: true)
        case .permission:
            let headline = permissionHeadline(toolName: pending.toolName)
            let command = singleLine(pending.text).map { headline.showsPrompt ? shellPrompt + $0 : $0 }
            return AgentsActivityLines(headline: headline.toolName + " " + headline.verb, detail: command.map(AgentsActivityLines.Detail.command), emphasizesDetail: true)
        case .question:
            let hasTwoRowsOfActions = AgentsActivityActions.actions(for: pending, agentId: "").count > singleRowActionLimit
            return AgentsActivityLines(
                headline: singleLine(pending.text) ?? PendingText.questionHeader,
                detail: hasTwoRowsOfActions ? nil : .continuation,
                emphasizesDetail: true
            )
        }
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
