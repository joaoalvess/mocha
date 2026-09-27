import Foundation

public struct AgentsActivityContent: Codable, Hashable, Sendable {
    public var working: Int
    public var waiting: Int
    public var highlight: Highlight?
    public var pending: Pending?
    public var updatedAt: Date

    public init(working: Int, waiting: Int, highlight: Highlight?, pending: Pending? = nil, updatedAt: Date) {
        self.working = working
        self.waiting = waiting
        self.highlight = highlight
        self.pending = pending
        self.updatedAt = updatedAt
    }

    public struct Highlight: Codable, Hashable, Sendable {
        public var agentId: String
        public var title: String
        public var workspaceLabel: String
        public var status: String
        public var since: Date

        public init(agentId: String, title: String, workspaceLabel: String, status: String, since: Date) {
            self.agentId = agentId
            self.title = title
            self.workspaceLabel = workspaceLabel
            self.status = status
            self.since = since
        }
    }

    public struct Pending: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable {
            case permission
            case question
        }

        public var requestId: String
        public var agentId: String
        public var kind: Kind
        public var toolName: String?
        public var text: String
        public var options: [String]

        public init(requestId: String, agentId: String, kind: Kind, toolName: String?, text: String, options: [String]) {
            self.requestId = requestId
            self.agentId = agentId
            self.kind = kind
            self.toolName = toolName
            self.text = text
            self.options = options
        }
    }

    public var isBusy: Bool {
        working > 0 || waiting > 0
    }

    public func clearingPending(_ requestId: String) -> AgentsActivityContent? {
        guard pending?.requestId == requestId else { return nil }
        var cleared = self
        cleared.pending = nil
        return cleared
    }
}
