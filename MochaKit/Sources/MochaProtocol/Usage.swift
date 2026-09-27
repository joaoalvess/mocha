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
    public var windowDurationMins: Int?
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(kind: UsageWindowKind, usedPercent: Double, resetsAt: Date? = nil, windowDurationMins: Int? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }

    private enum CodingKeys: String, CodingKey {
        case kind, usedPercent, resetsAt, windowDurationMins
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(UsageWindowKind.self, forKey: .kind)
        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        resetsAt = try container.decodeProtocolDateIfPresent(forKey: .resetsAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(windowDurationMins, forKey: .windowDurationMins)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encodeProtocolDateIfPresent(resetsAt, forKey: .resetsAt)
    }
}

public struct UsageSnapshot: Codable, Sendable, Hashable {
    public var provider: AgentProvider
    public var plan: String?
    public var account: String?
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(provider: AgentProvider = .claude, plan: String? = nil, account: String? = nil, windows: [UsageWindow], fetchedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.account = account
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case provider, plan, account, windows, fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .claude
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        account = try container.decodeIfPresent(String.self, forKey: .account)
        windows = try container.decodeLossyArray(of: UsageWindow.self, forKey: .windows)
        fetchedAt = try container.decodeProtocolDate(forKey: .fetchedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if provider != .claude {
            try container.encode(provider, forKey: .provider)
        }
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(account, forKey: .account)
        try container.encode(windows, forKey: .windows)
        try container.encodeProtocolDate(fetchedAt, forKey: .fetchedAt)
    }
}
