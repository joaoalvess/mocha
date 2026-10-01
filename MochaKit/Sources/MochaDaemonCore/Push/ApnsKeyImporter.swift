import Foundation

public struct ApnsKeyImporter: Sendable {
    private let keyStore: any ApnsKeyStoring
    private let configStore: ApnsConfigStore

    public init(keyStore: any ApnsKeyStoring = KeychainApnsKeyStore(), configStore: ApnsConfigStore = ApnsConfigStore()) {
        self.keyStore = keyStore
        self.configStore = configStore
    }

    public func importKey(fileURL: URL, keyId: String, teamId: String, bundleId: String) throws -> ApnsConfig {
        guard ApnsIdentifier.isValid(keyId) else { throw ApnsError.invalidKeyId }
        guard ApnsIdentifier.isValid(teamId) else { throw ApnsError.invalidTeamId }
        guard ApnsIdentifier.isValidBundleId(bundleId) else { throw ApnsError.invalidBundleId }
        guard let pem = String(data: try Data(contentsOf: fileURL), encoding: .utf8) else {
            throw ApnsError.invalidPrivateKey
        }
        try ApnsSigningKey.validatePEM(pem)
        try keyStore.save(pem: pem, keyId: keyId)
        let config = ApnsConfig(teamId: teamId, keyId: keyId, bundleId: bundleId)
        try configStore.write(config)
        return config
    }

    public func loadSigningKey() throws -> (config: ApnsConfig, key: ApnsSigningKey) {
        guard let config = try configStore.read() else { throw ApnsError.notConfigured }
        let pem = try keyStore.load(keyId: config.keyId)
        return (config, try ApnsSigningKey(keyId: config.keyId, teamId: config.teamId, pem: pem))
    }
}
