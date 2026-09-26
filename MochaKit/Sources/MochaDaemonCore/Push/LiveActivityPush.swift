import Foundation

public struct LiveActivityContentState: Codable, Sendable, Equatable {
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

    public struct Highlight: Codable, Sendable, Equatable {
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

        enum CodingKeys: String, CodingKey {
            case agentId, title, workspaceLabel, status, since
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            agentId = try container.decode(String.self, forKey: .agentId)
            title = try container.decode(String.self, forKey: .title)
            workspaceLabel = try container.decode(String.self, forKey: .workspaceLabel)
            status = try container.decode(String.self, forKey: .status)
            since = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .since))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(agentId, forKey: .agentId)
            try container.encode(title, forKey: .title)
            try container.encode(workspaceLabel, forKey: .workspaceLabel)
            try container.encode(status, forKey: .status)
            try container.encode(since.timeIntervalSinceReferenceDate, forKey: .since)
        }
    }

    enum CodingKeys: String, CodingKey {
        case working, waiting, highlight, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        working = try container.decode(Int.self, forKey: .working)
        waiting = try container.decode(Int.self, forKey: .waiting)
        highlight = try container.decodeIfPresent(Highlight.self, forKey: .highlight)
        updatedAt = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .updatedAt))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(working, forKey: .working)
        try container.encode(waiting, forKey: .waiting)
        try container.encodeIfPresent(highlight, forKey: .highlight)
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
