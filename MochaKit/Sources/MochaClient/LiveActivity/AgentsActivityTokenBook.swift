import Foundation
import MochaProtocol

public struct AgentsActivityTokenBook: Codable, Equatable, Sendable {
    public struct Token: Codable, Equatable, Sendable {
        public var value: String
        public var agentId: String?
        public var isDelivered: Bool

        public init(value: String, agentId: String? = nil, isDelivered: Bool = false) {
            self.value = value
            self.agentId = agentId
            self.isDelivered = isDelivered
        }
    }

    public private(set) var environment: ApnsEnvironment?
    public private(set) var pushToStart: Token?
    public private(set) var activities: [String: Token] = [:]

    public init() {}

    public var hasUndelivered: Bool {
        pushToStart?.isDelivered == false || activities.values.contains { !$0.isDelivered }
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
    public mutating func recordUpdateToken(_ value: String, activityId: String, agentId: String) -> Bool {
        guard activities[activityId]?.value != value || activities[activityId]?.agentId != agentId else { return false }
        activities[activityId] = Token(value: value, agentId: agentId)
        return true
    }

    @discardableResult
    public mutating func forgetActivity(_ activityId: String) -> Bool {
        activities.removeValue(forKey: activityId) != nil
    }

    @discardableResult
    public mutating func forgetActivities(except activityIds: Set<String>) -> Bool {
        let kept = activities.filter { activityIds.contains($0.key) }
        guard kept.count != activities.count else { return false }
        activities = kept
        return true
    }

    public func registrations(includingDelivered: Bool) -> [LiveActivityRegistration] {
        guard let environment else { return [] }
        let pushToStartToken = pushToStart?.value
        let activityRegistrations = activities
            .sorted { $0.key < $1.key }
            .filter { includingDelivered || !$0.value.isDelivered }
            .map {
                LiveActivityRegistration(pushToStartToken: pushToStartToken, activityId: $0.key, updateToken: $0.value.value, agentId: $0.value.agentId, env: environment)
            }
        guard activityRegistrations.isEmpty else { return activityRegistrations }
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
