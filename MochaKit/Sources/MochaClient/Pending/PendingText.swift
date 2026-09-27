import Foundation
import MochaProtocol

public struct PendingPermissionText: Sendable, Equatable {
    public var toolName: String
    public var verb: String
    public var detail: String?
    public var showsPrompt: Bool
    public var fullInput: String

    public init(toolName: String, verb: String, detail: String?, showsPrompt: Bool, fullInput: String) {
        self.toolName = toolName
        self.verb = verb
        self.detail = detail
        self.showsPrompt = showsPrompt
        self.fullInput = fullInput
    }
}

public struct PendingNotice: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum PendingText {
    public static let permissionHeader = "Precisa de você"
    public static let questionHeader = "Pergunta do Claude"
    public static let inboxTitle = "Precisa de você"
    public static let emptyInbox = "Nada esperando você."
    public static let showFullInput = "Ver entrada completa"
    public static let hideFullInput = "Ocultar entrada completa"
    public static let allow = "Permitir"
    public static let deny = "Negar"
    public static let answer = "Responder"
    public static let otherPlaceholder = "Outro…"
    public static let answerPlaceholder = "Sua resposta"
    public static let send = "Enviar"
    public static let unknownAgent = "Claude"
    public static let unreachableTitle = "Não consegui falar com o Mac"
    public static let unreachableBody = "A resposta não foi enviada. Abra o Mocha para responder."
    public static let refusedTitle = "O Mac recusou a resposta"
    public static let refusedBody = "Abra o Mocha para responder."
    public static let unpairedBody = "Este iPhone não está mais pareado."

    public static func header(for kind: PendingKind) -> String {
        switch kind {
        case .permission: permissionHeader
        case .question: questionHeader
        }
    }

    public static func permission(toolName: String, summary: String, inputJSON: String) -> PendingPermissionText {
        let detail = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return PendingPermissionText(
            toolName: ToolPresentation.displayName(for: toolName),
            verb: verb(forTool: toolName),
            detail: detail.isEmpty ? nil : detail,
            showsPrompt: ToolPresentation.icon(for: toolName) == .shell,
            fullInput: formattedInput(inputJSON)
        )
    }

    public static func verb(forTool toolName: String) -> String {
        switch toolName {
        case "Bash", "BashOutput", "KillShell": "quer rodar"
        case "Read", "NotebookRead": "quer ler"
        case "Edit", "MultiEdit", "NotebookEdit": "quer editar"
        case "Write": "quer escrever"
        case "WebFetch": "quer abrir"
        case "WebSearch", "Grep", "Glob": "quer buscar"
        default: "quer usar"
        }
    }

    public static func age(from createdAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(createdAt)))
        switch seconds {
        case ..<1:
            return "agora"
        case ..<minute:
            return "há \(seconds) s"
        case ..<hour:
            return "há \(seconds / minute) min"
        default:
            return "há \(seconds / hour) h"
        }
    }

    public static func inboxMeta(workspace: String?, createdAt: Date, now: Date) -> String {
        let age = age(from: createdAt, now: now)
        guard let workspace = workspace?.trimmingCharacters(in: .whitespacesAndNewlines), !workspace.isEmpty else { return age }
        return "\(workspace) · \(age)"
    }

    public static func inboxCount(_ count: Int) -> String {
        "· \(max(0, count))"
    }

    public static func badge(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > badgeLimit ? "\(badgeLimit)+" : "\(count)"
    }

    public static func formattedInput(_ inputJSON: String) -> String {
        guard
            let data = inputJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            JSONSerialization.isValidJSONObject(object),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let text = String(data: pretty, encoding: .utf8)
        else { return inputJSON }
        return text
    }

    public static func failureNotice(for result: PendingRespondResult) -> PendingNotice? {
        switch result {
        case .accepted, .gone:
            nil
        case .refused:
            PendingNotice(title: refusedTitle, body: refusedBody)
        case .unauthorized, .notPaired:
            PendingNotice(title: unreachableTitle, body: unpairedBody)
        case .unreachable, .unexpectedStatus:
            PendingNotice(title: unreachableTitle, body: unreachableBody)
        }
    }

    private static let minute = 60
    private static let hour = 60 * minute
    private static let badgeLimit = 99
}
