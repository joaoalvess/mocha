import Foundation

public struct LiveActivityContentState: Codable, Sendable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case working, waiting, highlight, pending, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        working = try container.decode(Int.self, forKey: .working)
        waiting = try container.decode(Int.self, forKey: .waiting)
        highlight = try container.decodeIfPresent(Highlight.self, forKey: .highlight)
        pending = try container.decodeIfPresent(Pending.self, forKey: .pending)
        updatedAt = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .updatedAt))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(working, forKey: .working)
        try container.encode(waiting, forKey: .waiting)
        try container.encodeIfPresent(highlight, forKey: .highlight)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encode(updatedAt.timeIntervalSinceReferenceDate, forKey: .updatedAt)
    }
}

public struct LiveActivityStartAlert: Sendable, Equatable {
    public var title: String
    public var body: String
    public var sound: String?

    public init(title: String, body: String, sound: String? = nil) {
        self.title = title
        self.body = body
        self.sound = sound
    }
}

public enum LiveActivityEvent: Sendable, Equatable {
    case start(alert: LiveActivityStartAlert)
    case update
    case end(dismissalDate: Date?)

    var name: String {
        switch self {
        case .start: "start"
        case .update: "update"
        case .end: "end"
        }
    }
}

public struct LiveActivityPush: Sendable, Equatable {
    public static let attributesType = "MochaAgentsAttributes"

    public var event: LiveActivityEvent
    public var contentState: LiveActivityContentState
    public var timestamp: Date
    public var staleDate: Date?

    public init(event: LiveActivityEvent, contentState: LiveActivityContentState, timestamp: Date, staleDate: Date? = nil) {
        self.event = event
        self.contentState = contentState
        self.timestamp = timestamp
        self.staleDate = staleDate
    }

    public func payload() throws -> Data {
        var aps = Aps(
            timestamp: ApnsPayloadEncoding.unixSeconds(timestamp),
            event: event.name,
            contentState: contentState,
            staleDate: staleDate.map(ApnsPayloadEncoding.unixSeconds)
        )
        switch event {
        case .start(let alert):
            aps.attributesType = Self.attributesType
            aps.attributes = EmptyAttributes()
            aps.alert = Alert(title: alert.title, body: alert.body, sound: alert.sound)
            aps.inputPushToken = 1
        case .update:
            break
        case .end(let dismissalDate):
            aps.dismissalDate = dismissalDate.map(ApnsPayloadEncoding.unixSeconds)
        }
        return try ApnsPayloadEncoding.encoder.encode(Body(aps: aps))
    }

    private struct Body: Encodable {
        let aps: Aps
    }

    private struct Aps: Encodable {
        let timestamp: Int64
        let event: String
        let contentState: LiveActivityContentState
        let staleDate: Int64?
        var dismissalDate: Int64?
        var attributesType: String?
        var attributes: EmptyAttributes?
        var alert: Alert?
        var inputPushToken: Int?

        init(timestamp: Int64, event: String, contentState: LiveActivityContentState, staleDate: Int64?) {
            self.timestamp = timestamp
            self.event = event
            self.contentState = contentState
            self.staleDate = staleDate
        }

        enum CodingKeys: String, CodingKey {
            case timestamp
            case event
            case contentState = "content-state"
            case staleDate = "stale-date"
            case dismissalDate = "dismissal-date"
            case attributesType = "attributes-type"
            case attributes
            case alert
            case inputPushToken = "input-push-token"
        }
    }

    private struct EmptyAttributes: Encodable {}

    private struct Alert: Encodable {
        let title: String
        let body: String
        let sound: String?
    }
}
