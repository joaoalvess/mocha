import Foundation

public actor ApnsTokenProvider {
    public static let refreshInterval: TimeInterval = 40 * 60

    private let key: ApnsSigningKey
    private let now: @Sendable () -> Date
    private var cached: (token: String, issuedAt: Date)?

    public init(key: ApnsSigningKey, now: @escaping @Sendable () -> Date = { Date() }) {
        self.key = key
        self.now = now
    }

    public func token() throws -> String {
        let current = now()
        if let cached, current >= cached.issuedAt, current.timeIntervalSince(cached.issuedAt) < Self.refreshInterval {
            return cached.token
        }
        let token = try ApnsJWT.make(key: key, issuedAt: current)
        cached = (token, current)
        return token
    }

    public func invalidate() {
        cached = nil
    }
}
