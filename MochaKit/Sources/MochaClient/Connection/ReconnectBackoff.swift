public struct ReconnectBackoff: Sendable, Equatable {
    public static let delaysInMilliseconds = [500, 1_000, 2_000, 4_000, 8_000]
    public static let maximumDelayInMilliseconds = 8_000
    public static let jitterRange: ClosedRange<Double> = 0.8...1.2

    public private(set) var failures = 0

    public init() {}

    public mutating func nextDelay(jitter: Double) -> Duration {
        let base = Self.delaysInMilliseconds[min(failures, Self.delaysInMilliseconds.count - 1)]
        failures += 1
        let factor = min(max(jitter, Self.jitterRange.lowerBound), Self.jitterRange.upperBound)
        let milliseconds = min((Double(base) * factor).rounded(), Double(Self.maximumDelayInMilliseconds))
        return .milliseconds(Int(milliseconds))
    }

    public mutating func reset() {
        failures = 0
    }

    public static func randomJitter() -> Double {
        Double.random(in: jitterRange)
    }
}
