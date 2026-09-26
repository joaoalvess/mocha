import Foundation
import MochaProtocol

public struct TranscriptHeader: Sendable, Equatable {
    public var title: String?
    public var model: String?
    public var branch: String?
    public var permissionMode: String?
    public var claudeVersion: String?
    public var preview: MessagePreview?
    public var activity: ToolActivity?
    public var contextTokens: Int?
    public var sessionStartedAt: Date?
    public var turnStartedAt: Date?
    public var turnEndedAt: Date?

    public init(
        title: String? = nil,
        model: String? = nil,
        branch: String? = nil,
        permissionMode: String? = nil,
        claudeVersion: String? = nil,
        preview: MessagePreview? = nil,
        activity: ToolActivity? = nil,
        contextTokens: Int? = nil,
        sessionStartedAt: Date? = nil,
        turnStartedAt: Date? = nil,
        turnEndedAt: Date? = nil
    ) {
        self.title = title
        self.model = model
        self.branch = branch
        self.permissionMode = permissionMode
        self.claudeVersion = claudeVersion
        self.preview = preview
        self.activity = activity
        self.contextTokens = contextTokens
        self.sessionStartedAt = sessionStartedAt
        self.turnStartedAt = turnStartedAt
        self.turnEndedAt = turnEndedAt
    }

    mutating func absorb(_ line: ParsedLine) {
        if let version = line.version {
            claudeVersion = version
        }
        if sessionStartedAt == nil {
            sessionStartedAt = line.date
        }
        for effect in line.effects {
            switch effect {
            case .title(let value):
                title = value
            case .permissionMode(let value):
                permissionMode = value
            case .modelAndBranch(let model, let branch):
                self.model = model
                self.branch = branch
            case .contextTokens(let tokens):
                contextTokens = tokens
            case .turnStarted:
                turnStartedAt = line.date
            case .turnEnded:
                turnEndedAt = line.date
            default:
                break
            }
        }
    }
}
