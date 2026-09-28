#if os(iOS)
import ActivityKit
import Foundation

public struct MochaAgentAttributes: ActivityAttributes, Sendable {
    public var agentId: String

    public init(agentId: String) {
        self.agentId = agentId
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String
        public var title: String
        public var workspaceLabel: String
        public var since: Date
        public var model: String?
        public var provider: AgentProvider?
        public var contextLeftPercent: Int?
        public var preview: String?
        public var activity: String?
        public var prompt: String?
        public var pending: Pending?
        public var updatedAt: Date

        public init(
            status: String,
            title: String,
            workspaceLabel: String,
            since: Date,
            model: String? = nil,
            provider: AgentProvider? = nil,
            contextLeftPercent: Int? = nil,
            preview: String? = nil,
            activity: String? = nil,
            prompt: String? = nil,
            pending: Pending? = nil,
            updatedAt: Date
        ) {
            self.status = status
            self.title = title
            self.workspaceLabel = workspaceLabel
            self.since = since
            self.model = model
            self.provider = provider
            self.contextLeftPercent = contextLeftPercent
            self.preview = preview
            self.activity = activity
            self.prompt = prompt
            self.pending = pending
            self.updatedAt = updatedAt
        }

        public struct Pending: Codable, Hashable, Sendable {
            public enum Kind: String, Codable, Hashable, Sendable {
                case permission
                case question
            }

            public var requestId: String
            public var kind: Kind
            public var toolName: String?
            public var text: String
            public var options: [String]

            public init(requestId: String, kind: Kind, toolName: String?, text: String, options: [String]) {
                self.requestId = requestId
                self.kind = kind
                self.toolName = toolName
                self.text = text
                self.options = options
            }
        }
    }
}
#endif
