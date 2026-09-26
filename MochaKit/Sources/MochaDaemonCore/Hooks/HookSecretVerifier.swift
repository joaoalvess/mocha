public actor HookSecretVerifier {
    public typealias Reload = @Sendable () -> String?

    private var secret: String?
    private let reload: Reload

    public init(secret: String?, reload: @escaping Reload = { nil }) {
        self.secret = secret
        self.reload = reload
    }

    public func accepts(_ presented: String?) -> Bool {
        guard let presented, !presented.isEmpty else { return false }
        if let secret, SecureToken.constantTimeEquals(secret, presented) {
            return true
        }
        guard let fresh = reload(), !fresh.isEmpty, fresh != secret else { return false }
        secret = fresh
        hooksLogger.info("hookSecret reloaded from config.json")
        return SecureToken.constantTimeEquals(fresh, presented)
    }
}
