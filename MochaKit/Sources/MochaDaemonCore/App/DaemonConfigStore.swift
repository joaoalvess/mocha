import Foundation

public struct DaemonConfig: Sendable, Equatable {
    public static let defaultHookPort: UInt16 = 47420
    public static let defaultGatewayPort: UInt16 = Gateway.port

    public var hookPort: UInt16
    public var gatewayPort: UInt16
    public var hookSecret: String?

    public init(
        hookPort: UInt16 = DaemonConfig.defaultHookPort,
        gatewayPort: UInt16 = DaemonConfig.defaultGatewayPort,
        hookSecret: String? = nil
    ) {
        self.hookPort = hookPort
        self.gatewayPort = gatewayPort
        self.hookSecret = hookSecret
    }
}

public enum DaemonConfigError: Error, Sendable, Equatable {
    case invalidJSON(path: String)
    case invalidPort(field: String)
}

public struct DaemonConfigStore: Sendable {
    public struct Preparation: Sendable, Equatable {
        public let config: DaemonConfig
        public let generatedHookSecret: Bool
    }

    enum Field {
        static let hookPort = "hookPort"
        static let gatewayPort = "gatewayPort"
        static let hookSecret = "hookSecret"
    }

    public let url: URL

    public init(url: URL = DaemonPaths().configFile) {
        self.url = url
    }

    public func read() throws -> DaemonConfig {
        try Self.config(from: readObject() ?? [:])
    }

    public func prepareForDaemon() throws -> Preparation {
        let original = try readObject()
        var object = original ?? [:]
        var generated = false
        if (object[Field.hookSecret] as? String).map(\.isEmpty) ?? true {
            object[Field.hookSecret] = SecureToken.generate()
            generated = true
        }
        if object[Field.hookPort] == nil {
            object[Field.hookPort] = Int(DaemonConfig.defaultHookPort)
        }
        if object[Field.gatewayPort] == nil {
            object[Field.gatewayPort] = Int(DaemonConfig.defaultGatewayPort)
        }
        let config = try Self.config(from: object)
        if original.map({ !NSDictionary(dictionary: $0).isEqual(to: object) }) ?? true {
            try write(object)
        }
        return Preparation(config: config, generatedHookSecret: generated)
    }

    private func readObject() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.fileSystemPath) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DaemonConfigError.invalidJSON(path: url.fileSystemPath)
        }
        return object
    }

    private func write(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try AtomicFile.write(data, to: url, permissions: 0o600)
    }

    private static func config(from object: [String: Any]) throws -> DaemonConfig {
        DaemonConfig(
            hookPort: try port(object, Field.hookPort) ?? DaemonConfig.defaultHookPort,
            gatewayPort: try port(object, Field.gatewayPort) ?? DaemonConfig.defaultGatewayPort,
            hookSecret: (object[Field.hookSecret] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func port(_ object: [String: Any], _ field: String) throws -> UInt16? {
        guard let value = object[field] else { return nil }
        guard let number = value as? Int, let port = UInt16(exactly: number), port > 0 else {
            throw DaemonConfigError.invalidPort(field: field)
        }
        return port
    }
}
