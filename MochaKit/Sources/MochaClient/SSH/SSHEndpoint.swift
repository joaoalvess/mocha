import Foundation
import MochaProtocol

public struct SSHHostKeyPin: Sendable, Equatable {
    public let keys: Set<String>

    public init?(hostKeys: [String]?) {
        let keys = Set((hostKeys ?? []).compactMap(Self.normalize))
        guard !keys.isEmpty else { return nil }
        self.keys = keys
    }

    public func accepts(_ presented: String) -> Bool {
        guard let key = Self.normalize(presented) else { return false }
        return keys.contains(key)
    }

    public static func normalize(_ line: String) -> String? {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else { return nil }
        return "\(fields[0]) \(fields[1])"
    }
}

public enum SSHEndpointError: Error, Equatable, LocalizedError {
    case notPaired
    case outdatedDaemon

    public var errorDescription: String? {
        switch self {
        case .notPaired: "Este iPhone não está pareado com um Mac"
        case .outdatedDaemon: "Atualize o mochad no Mac"
        }
    }
}

public struct SSHEndpoint: Sendable, Equatable {
    public static let defaultPort = 22

    public var host: String
    public var port: Int
    public var username: String
    public var hostKeys: SSHHostKeyPin

    public init(host: String, port: Int = SSHEndpoint.defaultPort, username: String, hostKeys: SSHHostKeyPin) {
        self.host = host
        self.port = port
        self.username = username
        self.hostKeys = hostKeys
    }

    public static func resolve(gatewayURL: URL?, hostInfo: HostInfo?) throws(SSHEndpointError) -> SSHEndpoint {
        guard let host = gatewayURL?.host(), !host.isEmpty, let hostInfo else { throw .notPaired }
        guard
            let username = hostInfo.sshUser?.trimmingCharacters(in: .whitespacesAndNewlines),
            !username.isEmpty,
            let hostKeys = SSHHostKeyPin(hostKeys: hostInfo.sshHostKeys)
        else { throw .outdatedDaemon }
        return SSHEndpoint(host: host, username: username, hostKeys: hostKeys)
    }
}
