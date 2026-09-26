import Foundation

public struct TranscriptHeader: Sendable, Equatable {
    public var title: String?
    public var model: String?
    public var branch: String?
    public var permissionMode: String?
    public var claudeVersion: String?

    public init(
        title: String? = nil,
        model: String? = nil,
        branch: String? = nil,
        permissionMode: String? = nil,
        claudeVersion: String? = nil
    ) {
        self.title = title
        self.model = model
        self.branch = branch
        self.permissionMode = permissionMode
        self.claudeVersion = claudeVersion
    }

    mutating func absorb(_ line: ParsedLine) {
        if let version = line.version {
            claudeVersion = version
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
            default:
                break
            }
        }
    }
}
