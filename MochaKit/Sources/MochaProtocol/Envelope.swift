enum EnvelopeCodingKey: String, CodingKey {
    case version = "v"
    case id
    case type
    case payload
}

extension KeyedDecodingContainer where Key == EnvelopeCodingKey {
    func payload<PayloadKey: CodingKey>(keyedBy type: PayloadKey.Type) throws -> KeyedDecodingContainer<PayloadKey> {
        try nestedContainer(keyedBy: type, forKey: .payload)
    }

    func payloadIfPresent<PayloadKey: CodingKey>(keyedBy type: PayloadKey.Type) throws -> KeyedDecodingContainer<PayloadKey>? {
        guard contains(.payload), try !decodeNil(forKey: .payload) else { return nil }
        return try nestedContainer(keyedBy: type, forKey: .payload)
    }
}

extension KeyedEncodingContainer where Key == EnvelopeCodingKey {
    mutating func emptyPayload() {
        _ = nestedContainer(keyedBy: EnvelopeCodingKey.self, forKey: .payload)
    }
}

public struct ClientEnvelope: Codable, Sendable, Hashable {
    public var version: Int
    public var id: String
    public var message: ClientMessage

    public init(version: Int = ProtocolVersion.current, id: String, message: ClientMessage) {
        self.version = version
        self.id = id
        self.message = message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeCodingKey.self)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(String.self, forKey: .id)
        message = try ClientMessage(type: try container.decode(String.self, forKey: .type), envelope: container)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeCodingKey.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(message.type, forKey: .type)
        try message.encodePayload(into: &container)
    }
}

public struct ServerEnvelope: Codable, Sendable, Hashable {
    public var version: Int
    public var id: String?
    public var message: ServerMessage

    public init(version: Int = ProtocolVersion.current, id: String? = nil, message: ServerMessage) {
        self.version = version
        self.id = id
        self.message = message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeCodingKey.self)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        message = try ServerMessage(type: try container.decode(String.self, forKey: .type), envelope: container)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeCodingKey.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(message.type, forKey: .type)
        try message.encodePayload(into: &container)
    }
}

public struct EnvelopeHeader: Decodable, Sendable, Hashable {
    public var version: Int?
    public var id: String?
    public var type: String?

    public init(version: Int? = nil, id: String? = nil, type: String? = nil) {
        self.version = version
        self.id = id
        self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EnvelopeCodingKey.self)
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
    }
}
