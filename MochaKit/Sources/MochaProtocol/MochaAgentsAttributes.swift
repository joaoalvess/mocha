#if os(iOS)
import ActivityKit
import Foundation

public struct MochaAgentsAttributes: ActivityAttributes, Sendable {
    public init() {}

    public struct ContentState: Codable, Hashable, Sendable {
        public var working: Int
        public var waiting: Int
        public var highlight: Highlight?
        public var updatedAt: Date

        public init(working: Int, waiting: Int, highlight: Highlight?, updatedAt: Date) {
            self.working = working
            self.waiting = waiting
            self.highlight = highlight
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
    }
}
#endif
