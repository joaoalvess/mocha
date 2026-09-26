public struct HerdrBridgeConfiguration: Sendable {
    public var reconnectInterval: Duration
    public var snapshotDebounce: Duration
    public var treeDebounce: Duration
    public var paneUpdateProbeDelay: Duration
    public var agentDetectedProbeDelays: [Duration]
    public var reconciliationInterval: Duration

    public init(
        reconnectInterval: Duration = .seconds(2),
        snapshotDebounce: Duration = .milliseconds(150),
        treeDebounce: Duration = .milliseconds(150),
        paneUpdateProbeDelay: Duration = .seconds(1),
        agentDetectedProbeDelays: [Duration] = [.seconds(1), .seconds(3)],
        reconciliationInterval: Duration = .seconds(5)
    ) {
        self.reconnectInterval = reconnectInterval
        self.snapshotDebounce = snapshotDebounce
        self.treeDebounce = treeDebounce
        self.paneUpdateProbeDelay = paneUpdateProbeDelay
        self.agentDetectedProbeDelays = agentDetectedProbeDelays
        self.reconciliationInterval = reconciliationInterval
    }
}
