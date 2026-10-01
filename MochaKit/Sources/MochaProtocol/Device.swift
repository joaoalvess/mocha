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
    public var silenceWhileAtMac: Bool

    public init(turnDoneAlerts: Bool = true, silenceWhileAtMac: Bool = true) {
        self.turnDoneAlerts = turnDoneAlerts
        self.silenceWhileAtMac = silenceWhileAtMac
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnDoneAlerts = try container.decode(Bool.self, forKey: .turnDoneAlerts)
        silenceWhileAtMac = try container.decodeIfPresent(Bool.self, forKey: .silenceWhileAtMac) ?? true
    }
}

public struct HostInfo: Codable, Sendable, Hashable {
    public var hostName: String
    public var daemonVersion: String
    public var herdrConnected: Bool
    public var sshUser: String?
    public var sshHostKeys: [String]?

    public init(hostName: String, daemonVersion: String, herdrConnected: Bool, sshUser: String? = nil, sshHostKeys: [String]? = nil) {
        self.hostName = hostName
        self.daemonVersion = daemonVersion
        self.herdrConnected = herdrConnected
        self.sshUser = sshUser
        self.sshHostKeys = sshHostKeys
    }
}

public struct LiveActivityRegistration: Codable, Sendable, Hashable {
    public var pushToStartToken: String?
    public var activityId: String?
    public var updateToken: String?
    public var agentId: String?
    public var env: ApnsEnvironment
    public var endedActivityId: String?

    public init(
        pushToStartToken: String? = nil,
        activityId: String? = nil,
        updateToken: String? = nil,
        agentId: String? = nil,
        env: ApnsEnvironment,
        endedActivityId: String? = nil
    ) {
        self.pushToStartToken = pushToStartToken
        self.activityId = activityId
        self.updateToken = updateToken
        self.agentId = agentId
        self.env = env
        self.endedActivityId = endedActivityId
    }
}
