import Foundation

public protocol GatewayClock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemGatewayClock: GatewayClock {
    public init() {}

    public func now() -> Date {
        Date()
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
