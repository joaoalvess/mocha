import Foundation

public enum LiveActivityContentState {
    public struct Pending: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable, Equatable {
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

    public struct Highlight: Codable, Sendable, Equatable {
        public var agentId: String
        public var title: String
        public var workspaceLabel: String
        public var status: String
        public var since: Date
        public var tabTitle: String?
        public var model: String?
        public var contextLeftPercent: Int?
        public var preview: String?
        public var activity: String?

        public init(
            agentId: String,
            title: String,
            workspaceLabel: String,
            status: String,
            since: Date,
            tabTitle: String? = nil,
            model: String? = nil,
            contextLeftPercent: Int? = nil,
            preview: String? = nil,
            activity: String? = nil
        ) {
            self.agentId = agentId
            self.title = title
            self.workspaceLabel = workspaceLabel
            self.status = status
            self.since = since
            self.tabTitle = tabTitle
            self.model = model
            self.contextLeftPercent = contextLeftPercent
            self.preview = preview
            self.activity = activity
        }

        enum CodingKeys: String, CodingKey {
            case agentId, title, workspaceLabel, status, since, tabTitle, model, contextLeftPercent, preview, activity
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            agentId = try container.decode(String.self, forKey: .agentId)
            title = try container.decode(String.self, forKey: .title)
            workspaceLabel = try container.decode(String.self, forKey: .workspaceLabel)
            status = try container.decode(String.self, forKey: .status)
            since = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .since))
            tabTitle = try container.decodeIfPresent(String.self, forKey: .tabTitle)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            contextLeftPercent = try container.decodeIfPresent(Int.self, forKey: .contextLeftPercent)
            preview = try container.decodeIfPresent(String.self, forKey: .preview)
            activity = try container.decodeIfPresent(String.self, forKey: .activity)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(agentId, forKey: .agentId)
            try container.encode(title, forKey: .title)
            try container.encode(workspaceLabel, forKey: .workspaceLabel)
            try container.encode(status, forKey: .status)
            try container.encode(since.timeIntervalSinceReferenceDate, forKey: .since)
            try container.encodeIfPresent(tabTitle, forKey: .tabTitle)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(contextLeftPercent, forKey: .contextLeftPercent)
            try container.encodeIfPresent(preview, forKey: .preview)
            try container.encodeIfPresent(activity, forKey: .activity)
        }
    }
}
