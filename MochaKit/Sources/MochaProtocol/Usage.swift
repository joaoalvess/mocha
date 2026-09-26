import Foundation

public enum UsageWindowKind: String, Codable, Sendable, Hashable {
    case fiveHour
    case weekly
    case unknown

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = UsageWindowKind(rawValue: rawValue) ?? .unknown
    }
}

public struct UsageWindow: Codable, Sendable, Hashable {
    public var kind: UsageWindowKind
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(kind: UsageWindowKind, usedPercent: Double, resetsAt: Date? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind, usedPercent, resetsAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(UsageWindowKind.self, forKey: .kind)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        resetsAt = try container.decodeProtocolDateIfPresent(forKey: .resetsAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encodeProtocolDateIfPresent(resetsAt, forKey: .resetsAt)
    }
}

public struct UsageSnapshot: Codable, Sendable, Hashable {
    public var plan: String?
    public var account: String?
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(plan: String? = nil, account: String? = nil, windows: [UsageWindow], fetchedAt: Date) {
        self.plan = plan
        self.account = account
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case plan, account, windows, fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        account = try container.decodeIfPresent(String.self, forKey: .account)
        windows = try container.decodeLossyArray(of: UsageWindow.self, forKey: .windows)
        fetchedAt = try container.decodeProtocolDate(forKey: .fetchedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(account, forKey: .account)
        try container.encode(windows, forKey: .windows)
        try container.encodeProtocolDate(fetchedAt, forKey: .fetchedAt)
    }
}
