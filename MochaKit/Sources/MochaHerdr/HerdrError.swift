import Foundation

public enum HerdrErrorCode: Sendable, Hashable {
    case invalidRequest
    case paneNotFound
    case agentNotFound
    case agentBlocked
    case agentNotReady
    case agentPromptStalled
    case invalidKey
    case timeout
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "invalid_request": self = .invalidRequest
        case "pane_not_found": self = .paneNotFound
        case "agent_not_found": self = .agentNotFound
        case "agent_blocked": self = .agentBlocked
        case "agent_not_ready": self = .agentNotReady
        case "agent_prompt_stalled": self = .agentPromptStalled
        case "invalid_key": self = .invalidKey
        case "timeout": self = .timeout
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .invalidRequest: "invalid_request"
        case .paneNotFound: "pane_not_found"
        case .agentNotFound: "agent_not_found"
        case .agentBlocked: "agent_blocked"
        case .agentNotReady: "agent_not_ready"
        case .agentPromptStalled: "agent_prompt_stalled"
        case .invalidKey: "invalid_key"
        case .timeout: "timeout"
        case .other(let value): value
        }
    }
}

public struct HerdrServerError: Error, Sendable, Hashable {
    public var requestId: String
    public var code: HerdrErrorCode
    public var message: String

    public init(requestId: String, code: HerdrErrorCode, message: String) {
        self.requestId = requestId
        self.code = code
        self.message = message
    }
}

public enum HerdrClientError: Error, Sendable, Hashable {
    case connectionFailed(String)
    case timeout(method: String)
    case closedWithoutResponse(method: String)
    case invalidResponse(method: String, detail: String)
    case server(HerdrServerError)

    public var isConnectionFailure: Bool {
        if case .connectionFailed = self { return true }
        return false
    }
}
