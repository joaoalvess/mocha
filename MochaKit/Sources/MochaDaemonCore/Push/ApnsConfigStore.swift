import Foundation

public struct ApnsConfig: Codable, Sendable, Equatable {
    public static let defaultBundleId = "com.example.mocha"

    public var teamId: String
    public var keyId: String
    public var bundleId: String

    public init(teamId: String, keyId: String, bundleId: String = Self.defaultBundleId) {
        self.teamId = teamId
        self.keyId = keyId
        self.bundleId = bundleId
    }
}

public struct ApnsConfigStore: Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Mocha/config.json")
    }

    public let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func read() throws -> ApnsConfig? {
        guard let object = try readObject(), let apns = object["apns"] else { return nil }
        let data = try JSONSerialization.data(withJSONObject: apns)
        do {
            return try JSONDecoder().decode(ApnsConfig.self, from: data)
        } catch {
            throw ApnsError.invalidConfig
        }
    }

    public func write(_ config: ApnsConfig) throws {
        var object = try readObject() ?? [:]
        let encoded = try JSONEncoder().encode(config)
        object["apns"] = try JSONSerialization.jsonObject(with: encoded)
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try AtomicFile.write(data, to: url, permissions: 0o600)
    }

    private func readObject() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApnsError.invalidConfig
        }
        return object
    }
}
