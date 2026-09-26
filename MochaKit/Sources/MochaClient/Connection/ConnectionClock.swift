public protocol ConnectionClock: Sendable {
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

public struct SystemConnectionClock: ConnectionClock {
    private let origin = ContinuousClock.now

    public init() {}

    public var now: Duration {
        ContinuousClock.now - origin
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
