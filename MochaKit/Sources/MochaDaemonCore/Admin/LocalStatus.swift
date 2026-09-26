import Foundation
import MochaProtocol

public struct LocalStatus: Codable, Sendable, Equatable {
    public struct Herdr: Codable, Sendable, Equatable {
        public var available: Bool
        public var version: String?
        public var protocolVersion: Int?

        public init(available: Bool, version: String? = nil, protocolVersion: Int? = nil) {
            self.available = available
            self.version = version
            self.protocolVersion = protocolVersion
        }

        private enum CodingKeys: String, CodingKey {
            case available, version
            case protocolVersion = "protocol"
        }
    }

    public struct Client: Codable, Sendable, Equatable {
        public var deviceId: DeviceID
        public var name: String
        public var connectedAt: Date

        public init(deviceId: DeviceID, name: String, connectedAt: Date) {
            self.deviceId = deviceId
            self.name = name
            self.connectedAt = connectedAt
        }
    }

    public struct Session: Codable, Sendable, Equatable {
        public var sessionId: String
        public var agentId: AgentID?
        public var claudeVersion: String?
        public var dropped: Int
        public var orphanResults: Int
        public var unknown: [String: Int]

        public init(sessionId: String, agentId: AgentID?, claudeVersion: String?, dropped: Int, orphanResults: Int, unknown: [String: Int]) {
            self.sessionId = sessionId
            self.agentId = agentId
            self.claudeVersion = claudeVersion
            self.dropped = dropped
            self.orphanResults = orphanResults
            self.unknown = unknown
        }
    }

    public struct Apns: Codable, Sendable, Equatable {
        public var configurationErrors: [ApnsConfigurationIssue]

        public init(configurationErrors: [ApnsConfigurationIssue]) {
            self.configurationErrors = configurationErrors
        }
    }

    public var version: String
    public var startedAt: Date
    public var herdr: Herdr
    public var clients: [Client]
    public var sessions: [Session]
    public var apns: Apns?

    public init(version: String, startedAt: Date, herdr: Herdr, clients: [Client], sessions: [Session], apns: Apns? = nil) {
        self.version = version
        self.startedAt = startedAt
        self.herdr = herdr
        self.clients = clients
        self.sessions = sessions
        self.apns = apns
    }
}

enum LocalJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ProtocolDate.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ProtocolDate.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(text)")
            }
            return date
        }
        return decoder
    }
}

extension PairingCode: Decodable {
    private enum DecodingKeys: String, CodingKey {
        case code, url, expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        let urlText = try container.decode(String.self, forKey: .url)
        guard let url = URL(string: urlText) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invalid URL: \(urlText)")
        }
        let expiresText = try container.decode(String.self, forKey: .expiresAt)
        guard let expiresAt = ProtocolDate.date(from: expiresText) else {
            throw DecodingError.dataCorruptedError(forKey: .expiresAt, in: container, debugDescription: "Invalid date: \(expiresText)")
        }
        self.init(code: try container.decode(String.self, forKey: .code), url: url, expiresAt: expiresAt)
    }
}

struct LocalErrorBody: Codable, Sendable, Equatable {
    var error: String
}
