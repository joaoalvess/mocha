public enum ApnsEnvironment: String, Codable, Sendable, Hashable {
    case sandbox
    case production
}

public struct ApnsRegistration: Codable, Sendable, Hashable {
    public var token: String
    public var env: ApnsEnvironment

    public init(token: String, env: ApnsEnvironment) {
        self.token = token
        self.env = env
    }
}

public struct DevicePreferences: Codable, Sendable, Hashable {
    public var turnDoneAlerts: Bool

    public init(turnDoneAlerts: Bool = true) {
        self.turnDoneAlerts = turnDoneAlerts
    }
}

public struct HostInfo: Codable, Sendable, Hashable {
    public var hostName: String
    public var daemonVersion: String
    public var herdrConnected: Bool

    public init(hostName: String, daemonVersion: String, herdrConnected: Bool) {
        self.hostName = hostName
        self.daemonVersion = daemonVersion
        self.herdrConnected = herdrConnected
    }
}

public struct LiveActivityRegistration: Codable, Sendable, Hashable {
    public var pushToStartToken: String?
    public var activityId: String?
    public var updateToken: String?
    public var env: ApnsEnvironment

    public init(pushToStartToken: String? = nil, activityId: String? = nil, updateToken: String? = nil, env: ApnsEnvironment) {
        self.pushToStartToken = pushToStartToken
        self.activityId = activityId
        self.updateToken = updateToken
        self.env = env
    }
}
