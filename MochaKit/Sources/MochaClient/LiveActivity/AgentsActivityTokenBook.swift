import Foundation
import MochaProtocol

public struct AgentsActivityTokenBook: Codable, Equatable, Sendable {
    public struct Token: Codable, Equatable, Sendable {
        public var value: String
        public var isDelivered: Bool

        public init(value: String, isDelivered: Bool = false) {
            self.value = value
            self.isDelivered = isDelivered
        }
    }

    public static let endedLimit = 8

    public private(set) var environment: ApnsEnvironment?
    public private(set) var pushToStart: Token?
    public private(set) var activities: [String: Token] = [:]
    public private(set) var ended: [String] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        environment = try container.decodeIfPresent(ApnsEnvironment.self, forKey: .environment)
        pushToStart = try container.decodeIfPresent(Token.self, forKey: .pushToStart)
        activities = try container.decode([String: Token].self, forKey: .activities)
        ended = try container.decodeIfPresent([String].self, forKey: .ended) ?? []
    }

    public var hasUndelivered: Bool {
        pushToStart?.isDelivered == false || activities.values.contains { !$0.isDelivered } || !ended.isEmpty
    }

    @discardableResult
    public mutating func use(_ environment: ApnsEnvironment) -> Bool {
        guard self.environment != environment else { return false }
        self.environment = environment
        pushToStart?.isDelivered = false
        for id in activities.keys {
            activities[id]?.isDelivered = false
        }
        return true
    }

    @discardableResult
    public mutating func recordPushToStartToken(_ value: String) -> Bool {
        guard pushToStart?.value != value else { return false }
        pushToStart = Token(value: value)
        return true
    }

    @discardableResult
    public mutating func recordUpdateToken(_ value: String, activityId: String) -> Bool {
        guard activities[activityId]?.value != value else { return false }
        activities[activityId] = Token(value: value)
        return true
    }

    @discardableResult
    public mutating func forgetActivity(_ activityId: String) -> Bool {
        guard activities.removeValue(forKey: activityId) != nil else { return false }
        rememberEnded(activityId)
        return true
    }

    @discardableResult
    public mutating func forgetActivities(except activityIds: Set<String>) -> Bool {
        let forgotten = activities.keys.filter { !activityIds.contains($0) }.sorted()
        guard !forgotten.isEmpty else { return false }
        activities = activities.filter { activityIds.contains($0.key) }
        forgotten.forEach { rememberEnded($0) }
        return true
    }

    private mutating func rememberEnded(_ activityId: String) {
        ended.removeAll { $0 == activityId }
        ended.append(activityId)
        ended = Array(ended.suffix(Self.endedLimit))
    }

    public func registrations(includingDelivered: Bool) -> [LiveActivityRegistration] {
        guard let environment else { return [] }
        let pushToStartToken = pushToStart?.value
        let activityRegistrations = activities
            .sorted { $0.key < $1.key }
            .filter { includingDelivered || !$0.value.isDelivered }
            .map {
                LiveActivityRegistration(pushToStartToken: pushToStartToken, activityId: $0.key, updateToken: $0.value.value, env: environment)
            }
        let endedRegistrations = ended.map {
            LiveActivityRegistration(pushToStartToken: pushToStartToken, env: environment, endedActivityId: $0)
        }
        guard activityRegistrations.isEmpty, endedRegistrations.isEmpty else { return activityRegistrations + endedRegistrations }
        guard let pushToStart, includingDelivered || !pushToStart.isDelivered else { return [] }
        return [LiveActivityRegistration(pushToStartToken: pushToStart.value, env: environment)]
    }

    @discardableResult
    public mutating func markDelivered(_ registration: LiveActivityRegistration) -> Bool {
        guard registration.env == environment else { return false }
        var changed = false
        if let token = registration.pushToStartToken, pushToStart?.value == token, pushToStart?.isDelivered == false {
            pushToStart?.isDelivered = true
            changed = true
        }
        if let activityId = registration.activityId, let token = registration.updateToken,
           activities[activityId]?.value == token, activities[activityId]?.isDelivered == false {
            activities[activityId]?.isDelivered = true
            changed = true
        }
        if let activityId = registration.endedActivityId, let index = ended.firstIndex(of: activityId) {
            ended.remove(at: index)
            changed = true
        }
        return changed
    }
}

public struct AgentsActivityTokenFile: Sendable {
    public static let fileName = "live-activity-tokens.json"

    public let url: URL

    public init(url: URL = URL.applicationSupportDirectory.appending(path: AgentsActivityTokenFile.fileName)) {
        self.url = url
    }

    public func load() -> AgentsActivityTokenBook {
        guard
            let data = try? Data(contentsOf: url),
            let book = try? JSONDecoder().decode(AgentsActivityTokenBook.self, from: data)
        else { return AgentsActivityTokenBook() }
        return book
    }

    public func save(_ book: AgentsActivityTokenBook) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(book).write(to: url, options: .atomic)
    }
}
