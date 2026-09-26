import MochaProtocol

public protocol UsageProviding: Sendable {
    func events() -> AsyncStream<UsageSnapshot?>
    var snapshot: UsageSnapshot? { get async }
    func contextUsedPercent(forSession sessionId: String) async -> Double?
}
