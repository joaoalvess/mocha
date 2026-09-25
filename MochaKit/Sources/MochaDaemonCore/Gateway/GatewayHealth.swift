public struct GatewayHealth: Codable, Sendable, Equatable {
    public let ok: Bool
    public let version: String
    public let herdr: Bool

    public init(ok: Bool, version: String, herdr: Bool) {
        self.ok = ok
        self.version = version
        self.herdr = herdr
    }
}
