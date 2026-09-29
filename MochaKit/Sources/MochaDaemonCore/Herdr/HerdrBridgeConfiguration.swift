public struct HerdrBridgeConfiguration: Sendable {
    public var reconnectInterval: Duration
    public var snapshotDebounce: Duration
    public var treeDebounce: Duration
    public var paneUpdateProbeDelay: Duration
    public var agentDetectedProbeDelays: [Duration]
    public var sessionStartProbeDelays: [Duration]
    public var reconciliationInterval: Duration
    public var newAgentReadyTimeout: Duration
    public var controls: ClaudeControlTiming

    public init(
        reconnectInterval: Duration = .seconds(2),
        snapshotDebounce: Duration = .milliseconds(150),
        treeDebounce: Duration = .milliseconds(150),
        paneUpdateProbeDelay: Duration = .seconds(1),
        agentDetectedProbeDelays: [Duration] = [.seconds(1), .seconds(3)],
        sessionStartProbeDelays: [Duration] = [.zero, .milliseconds(500), .milliseconds(1500), .milliseconds(3500)],
        reconciliationInterval: Duration = .seconds(5),
        newAgentReadyTimeout: Duration = .seconds(30),
        controls: ClaudeControlTiming = ClaudeControlTiming()
    ) {
        self.reconnectInterval = reconnectInterval
        self.snapshotDebounce = snapshotDebounce
        self.treeDebounce = treeDebounce
        self.paneUpdateProbeDelay = paneUpdateProbeDelay
        self.agentDetectedProbeDelays = agentDetectedProbeDelays
        self.sessionStartProbeDelays = sessionStartProbeDelays
        self.reconciliationInterval = reconciliationInterval
        self.newAgentReadyTimeout = newAgentReadyTimeout
        self.controls = controls
    }
}

public struct ClaudeControlTiming: Sendable {
    public var pollInterval: Duration
    public var keyTimeout: Duration
    public var maxModeKeys: Int
    public var selectorTimeout: Duration

    public init(
        pollInterval: Duration = .milliseconds(15),
        keyTimeout: Duration = .milliseconds(500),
        maxModeKeys: Int = 5,
        selectorTimeout: Duration = .seconds(2)
    ) {
        self.pollInterval = pollInterval
        self.keyTimeout = keyTimeout
        self.maxModeKeys = maxModeKeys
        self.selectorTimeout = selectorTimeout
    }
}
