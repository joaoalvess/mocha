public enum ApnsError: Error, Sendable, Equatable {
    case invalidKeyId
    case invalidTeamId
    case invalidBundleId
    case invalidPrivateKey
    case invalidDeviceToken
    case collapseIdTooLong(bytes: Int)
    case payloadTooLarge(bytes: Int)
    case keyNotFound(keyId: String)
    case keychain(status: Int32)
    case notConfigured
    case invalidConfig
    case notHTTPResponse
}
