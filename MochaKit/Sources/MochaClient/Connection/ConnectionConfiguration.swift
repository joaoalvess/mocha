public struct ConnectionConfiguration: Sendable, Equatable {
    public static let pingInterval: Duration = .seconds(5)
    public static let pongTimeout: Duration = .seconds(15)

    public var deviceName: String
    public var appVersion: String
    public var pingInterval: Duration
    public var pongTimeout: Duration

    public init(
        deviceName: String,
        appVersion: String,
        pingInterval: Duration = ConnectionConfiguration.pingInterval,
        pongTimeout: Duration = ConnectionConfiguration.pongTimeout
    ) {
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
    }
}
