import Foundation
import MochaProtocol

public struct ReceivedHook: Sendable, Equatable {
    public var agentId: AgentID
    public var receivedAt: Date
    public var event: HookEvent

    public init(agentId: AgentID, receivedAt: Date, event: HookEvent) {
        self.agentId = agentId
        self.receivedAt = receivedAt
        self.event = event
    }
}

public enum HookEvent: Sendable, Equatable {
    case sessionStart(SessionStartHook)
    case userPromptSubmit(UserPromptSubmitHook)
    case stop(StopHook)
    case notification(NotificationHook)
    case permissionRequest(PermissionRequestHook)

    public var name: HookEventName {
        switch self {
        case .sessionStart: .sessionStart
        case .userPromptSubmit: .userPromptSubmit
        case .stop: .stop
        case .notification: .notification
        case .permissionRequest: .permissionRequest
        }
    }

    public var context: HookContext {
        switch self {
        case .sessionStart(let hook): hook.context
        case .userPromptSubmit(let hook): hook.context
        case .stop(let hook): hook.context
        case .notification(let hook): hook.context
        case .permissionRequest(let hook): hook.context
        }
    }
}

public struct HookContext: Sendable, Equatable {
    public var sessionId: String
    public var transcriptPath: String?
    public var cwd: String?
    public var permissionMode: String?
    public var promptId: String?
    public var subagentId: String?
    public var subagentType: String?

    public init(
        sessionId: String,
        transcriptPath: String? = nil,
        cwd: String? = nil,
        permissionMode: String? = nil,
        promptId: String? = nil,
        subagentId: String? = nil,
        subagentType: String? = nil
    ) {
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.promptId = promptId
        self.subagentId = subagentId
        self.subagentType = subagentType
    }
}

public enum SessionStartSource: Sendable, Equatable {
    case startup
    case resume
    case clear
    case compact
    case fork
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "startup": self = .startup
        case "resume": self = .resume
        case "clear": self = .clear
        case "compact": self = .compact
        case "fork": self = .fork
        default: self = .other(rawValue)
        }
    }
}

public struct SessionStartHook: Sendable, Equatable {
    public var context: HookContext
    public var source: SessionStartSource
    public var model: String?

    public init(context: HookContext, source: SessionStartSource, model: String? = nil) {
        self.context = context
        self.source = source
        self.model = model
    }
}

public struct UserPromptSubmitHook: Sendable, Equatable {
    public var context: HookContext
    public var prompt: String

    public init(context: HookContext, prompt: String) {
        self.context = context
        self.prompt = prompt
    }
}

public struct StopHook: Sendable, Equatable {
    public var context: HookContext
    public var lastAssistantMessage: String?

    public init(context: HookContext, lastAssistantMessage: String? = nil) {
        self.context = context
        self.lastAssistantMessage = lastAssistantMessage
    }
}

public enum NotificationKind: Sendable, Equatable {
    case permissionPrompt
    case idlePrompt
    case elicitationDialog
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "permission_prompt": self = .permissionPrompt
        case "idle_prompt": self = .idlePrompt
        case "elicitation_dialog": self = .elicitationDialog
        default: self = .other(rawValue)
        }
    }
}

public struct NotificationHook: Sendable, Equatable {
    public var context: HookContext
    public var message: String
    public var kind: NotificationKind?
    public var title: String?

    public init(context: HookContext, message: String, kind: NotificationKind? = nil, title: String? = nil) {
        self.context = context
        self.message = message
        self.kind = kind
        self.title = title
    }
}

public struct PermissionRequestHook: Sendable, Equatable {
    public var context: HookContext
    public var toolName: String
    public var toolInput: OrderedJSON

    public init(context: HookContext, toolName: String, toolInput: OrderedJSON) {
        self.context = context
        self.toolName = toolName
        self.toolInput = toolInput
    }
}

public enum HookPayloadError: Error, Sendable, Equatable {
    case invalidJSON
    case notAnObject
    case missingField(String)
}

extension HookEvent {
    public static func decode(_ name: HookEventName, from body: Data) throws -> HookEvent {
        let json: OrderedJSON
        do {
            json = try OrderedJSON.parse(body)
        } catch {
            throw HookPayloadError.invalidJSON
        }
        guard json.members != nil else { throw HookPayloadError.notAnObject }
        let payload = HookPayload(json: json)
        let context = try payload.context()
        switch name {
        case .sessionStart:
            return .sessionStart(SessionStartHook(
                context: context,
                source: SessionStartSource(rawValue: try payload.required("source")),
                model: payload.optional("model")
            ))
        case .userPromptSubmit:
            return .userPromptSubmit(UserPromptSubmitHook(context: context, prompt: try payload.required("prompt")))
        case .stop:
            return .stop(StopHook(context: context, lastAssistantMessage: payload.optional("last_assistant_message")))
        case .notification:
            return .notification(NotificationHook(
                context: context,
                message: try payload.required("message"),
                kind: payload.optional("notification_type").map(NotificationKind.init(rawValue:)),
                title: payload.optional("title")
            ))
        case .permissionRequest:
            guard let toolInput = json["tool_input"], toolInput.members != nil else {
                throw HookPayloadError.missingField("tool_input")
            }
            return .permissionRequest(PermissionRequestHook(
                context: context,
                toolName: try payload.required("tool_name"),
                toolInput: toolInput
            ))
        }
    }
}

private struct HookPayload {
    let json: OrderedJSON

    func context() throws -> HookContext {
        HookContext(
            sessionId: try required("session_id"),
            transcriptPath: optional("transcript_path"),
            cwd: optional("cwd"),
            permissionMode: optional("permission_mode"),
            promptId: optional("prompt_id"),
            subagentId: optional("agent_id"),
            subagentType: optional("agent_type")
        )
    }

    func required(_ key: String) throws -> String {
        guard let value = json[key]?.stringValue else { throw HookPayloadError.missingField(key) }
        return value
    }

    func optional(_ key: String) -> String? {
        json[key]?.stringValue
    }
}
