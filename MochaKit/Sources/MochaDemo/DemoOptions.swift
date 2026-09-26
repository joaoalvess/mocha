public struct DemoOptions: Sendable, Equatable {
    public var startsPaired: Bool
    public var runsScript: Bool
    public var isEmpty: Bool
    public var connectDelay: Duration
    public var echoDelay: Duration
    public var replyDelay: Duration
    public var scriptTimeScale: Double

    public init(
        startsPaired: Bool = true,
        runsScript: Bool = false,
        isEmpty: Bool = false,
        connectDelay: Duration = .milliseconds(400),
        echoDelay: Duration = .seconds(1),
        replyDelay: Duration = .seconds(2),
        scriptTimeScale: Double = 1
    ) {
        self.startsPaired = startsPaired
        self.runsScript = runsScript
        self.isEmpty = isEmpty
        self.connectDelay = connectDelay
        self.echoDelay = echoDelay
        self.replyDelay = replyDelay
        self.scriptTimeScale = scriptTimeScale
    }
}
