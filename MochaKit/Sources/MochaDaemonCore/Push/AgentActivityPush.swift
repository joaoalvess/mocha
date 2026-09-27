import Foundation

public struct AgentActivityContentState: Encodable, Sendable, Equatable {
    public var agent: LiveActivityContentState.Highlight
    public var pending: LiveActivityContentState.Pending?
    public var updatedAt: Date

    public init(agent: LiveActivityContentState.Highlight, pending: LiveActivityContentState.Pending?, updatedAt: Date) {
        self.agent = agent
        self.pending = pending
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case pending, updatedAt
    }

    public func encode(to encoder: any Encoder) throws {
        try agent.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encode(updatedAt.timeIntervalSinceReferenceDate, forKey: .updatedAt)
    }
}

public struct AgentActivityAlert: Sendable, Equatable {
    public var title: String
    public var body: String
    public var sound: String?

    public init(title: String, body: String, sound: String? = "default") {
        self.title = title
        self.body = body
        self.sound = sound
    }
}

public enum AgentActivityEvent: Sendable, Equatable {
    case start(alert: AgentActivityAlert)
    case update(alert: AgentActivityAlert?)
    case end(dismissalDate: Date?)

    var name: String {
        switch self {
        case .start: "start"
        case .update: "update"
        case .end: "end"
        }
    }
}

public struct AgentActivityPush: Sendable, Equatable {
    public static let attributesType = "MochaFeedAttributes"

    public var agentId: String
    public var event: AgentActivityEvent
    public var contentState: AgentActivityContentState
    public var timestamp: Date
    public var staleDate: Date?
    public var relevanceScore: Double?

    public init(
        agentId: String,
        event: AgentActivityEvent,
        contentState: AgentActivityContentState,
        timestamp: Date,
        staleDate: Date? = nil,
        relevanceScore: Double? = nil
    ) {
        self.agentId = agentId
        self.event = event
        self.contentState = contentState
        self.timestamp = timestamp
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }

    public var fitsPayloadLimit: Bool {
        ((try? payload())?.count ?? .max) <= ApnsRequest.maxPayloadBytes
    }

    public func payload() throws -> Data {
        var aps = Aps(
            timestamp: ApnsPayloadEncoding.unixSeconds(timestamp),
            event: event.name,
            contentState: contentState,
            staleDate: staleDate.map(ApnsPayloadEncoding.unixSeconds),
            relevanceScore: relevanceScore
        )
        switch event {
        case .start(let alert):
            aps.attributesType = Self.attributesType
            aps.attributes = [:]
            aps.alert = Alert(alert)
            aps.inputPushToken = 1
        case .update(let alert):
            aps.alert = alert.map(Alert.init)
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
        let contentState: AgentActivityContentState
        let staleDate: Int64?
        let relevanceScore: Double?
        var dismissalDate: Int64?
        var attributesType: String?
        var attributes: [String: String]?
        var alert: Alert?
        var inputPushToken: Int?

        init(timestamp: Int64, event: String, contentState: AgentActivityContentState, staleDate: Int64?, relevanceScore: Double?) {
            self.timestamp = timestamp
            self.event = event
            self.contentState = contentState
            self.staleDate = staleDate
            self.relevanceScore = relevanceScore
        }

        enum CodingKeys: String, CodingKey {
            case timestamp
            case event
            case contentState = "content-state"
            case staleDate = "stale-date"
            case relevanceScore = "relevance-score"
            case dismissalDate = "dismissal-date"
            case attributesType = "attributes-type"
            case attributes
            case alert
            case inputPushToken = "input-push-token"
        }
    }

    private struct Alert: Encodable {
        let title: String
        let body: String
        let sound: String?

        init(_ alert: AgentActivityAlert) {
            title = alert.title
            body = alert.body
            sound = alert.sound
        }
    }
}
