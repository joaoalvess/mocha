import Foundation
import MochaProtocol

public struct DeviceRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: DeviceID
    public var name: String
    public var tokenSha256: String
    public var createdAt: Date
    public var lastSeenAt: Date
    public var apns: ApnsRegistration?
    public var preferences: DevicePreferences
    public var liveActivity: LiveActivityRegistration?
    public var agentActivities: [LiveActivityRegistration]

    public init(
        id: DeviceID,
        name: String,
        tokenSha256: String,
        createdAt: Date,
        lastSeenAt: Date,
        apns: ApnsRegistration? = nil,
        preferences: DevicePreferences = DevicePreferences(),
        liveActivity: LiveActivityRegistration? = nil,
        agentActivities: [LiveActivityRegistration] = []
    ) {
        self.id = id
        self.name = name
        self.tokenSha256 = tokenSha256
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.apns = apns
        self.preferences = preferences
        self.liveActivity = liveActivity
        self.agentActivities = agentActivities
    }

    public func hasLiveActivity(for agentId: AgentID) -> Bool {
        agentActivities.contains { $0.agentId == agentId && $0.updateToken != nil }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tokenSha256, createdAt, lastSeenAt, apns, preferences, liveActivity, agentActivities
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(DeviceID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tokenSha256 = try container.decode(String.self, forKey: .tokenSha256)
        createdAt = try Self.decodeDate(container, forKey: .createdAt)
        lastSeenAt = try Self.decodeDate(container, forKey: .lastSeenAt)
        apns = try container.decodeIfPresent(ApnsRegistration.self, forKey: .apns)
        preferences = try container.decodeIfPresent(DevicePreferences.self, forKey: .preferences) ?? DevicePreferences()
        liveActivity = try container.decodeIfPresent(LiveActivityRegistration.self, forKey: .liveActivity)
        agentActivities = try container.decodeIfPresent([LiveActivityRegistration].self, forKey: .agentActivities) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tokenSha256, forKey: .tokenSha256)
        try container.encode(ProtocolDate.string(from: createdAt), forKey: .createdAt)
        try container.encode(ProtocolDate.string(from: lastSeenAt), forKey: .lastSeenAt)
        try container.encodeIfPresent(apns, forKey: .apns)
        try container.encode(preferences, forKey: .preferences)
        try container.encodeIfPresent(liveActivity, forKey: .liveActivity)
        if !agentActivities.isEmpty {
            try container.encode(agentActivities, forKey: .agentActivities)
        }
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        let text = try container.decode(String.self, forKey: key)
        guard let date = ProtocolDate.date(from: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid ISO-8601 date: \(text)")
        }
        return date
    }
}
