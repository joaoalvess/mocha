public struct HelloOkPayload: Codable, Sendable, Hashable {
    public var host: HostInfo
    public var deviceId: DeviceID
    public var deviceToken: String?
    public var preferences: DevicePreferences

    public init(host: HostInfo, deviceId: DeviceID, deviceToken: String? = nil, preferences: DevicePreferences) {
        self.host = host
        self.deviceId = deviceId
        self.deviceToken = deviceToken
        self.preferences = preferences
    }
}

public struct ProtocolErrorCode: RawRepresentable, Codable, Sendable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let unauthorized = ProtocolErrorCode(rawValue: "unauthorized")
    public static let pairingExpired = ProtocolErrorCode(rawValue: "pairingExpired")
    public static let protocolMismatch = ProtocolErrorCode(rawValue: "protocolMismatch")
    public static let unknownType = ProtocolErrorCode(rawValue: "unknownType")
    public static let invalidPayload = ProtocolErrorCode(rawValue: "invalidPayload")
    public static let agentNotFound = ProtocolErrorCode(rawValue: "agentNotFound")
    public static let agentBlocked = ProtocolErrorCode(rawValue: "agentBlocked")
    public static let requestNotFound = ProtocolErrorCode(rawValue: "requestNotFound")
    public static let herdrUnavailable = ProtocolErrorCode(rawValue: "herdrUnavailable")
    public static let `internal` = ProtocolErrorCode(rawValue: "internal")
}

public enum ServerMessage: Sendable, Hashable {
    case helloOk(HelloOkPayload)
    case tree(workspaces: [WorkspaceNode])
    case treeChanged(workspaces: [WorkspaceNode])
    case agentStatus(agentId: AgentID, status: AgentStatus, title: String? = nil)
    case chatPage(ChatPage)
    case chatAppend(agentId: AgentID, items: [ChatItem])
    case chatUpdate(agentId: AgentID, items: [ChatItem])
    case chatMeta(agentId: AgentID, meta: ChatMeta)
    case pending(requests: [PendingRequest])
    case ack(agentId: AgentID? = nil)
    case pong
    case error(code: ProtocolErrorCode, message: String)
    case unknown(type: String)

    public var type: String {
        switch self {
        case .helloOk: "helloOk"
        case .tree: "tree"
        case .treeChanged: "treeChanged"
        case .agentStatus: "agentStatus"
        case .chatPage: "chatPage"
        case .chatAppend: "chatAppend"
        case .chatUpdate: "chatUpdate"
        case .chatMeta: "chatMeta"
        case .pending: "pending"
        case .ack: "ack"
        case .pong: "pong"
        case .error: "error"
        case .unknown(let type): type
        }
    }
}

extension ServerMessage {
    private enum PayloadKey: String, CodingKey {
        case workspaces, agentId, status, title, items, meta, requests, code, message
    }

    init(type: String, envelope: KeyedDecodingContainer<EnvelopeCodingKey>) throws {
        switch type {
        case "helloOk":
            self = .helloOk(try envelope.decode(HelloOkPayload.self, forKey: .payload))
        case "tree":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .tree(workspaces: try payload.decode([WorkspaceNode].self, forKey: .workspaces))
        case "treeChanged":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .treeChanged(workspaces: try payload.decode([WorkspaceNode].self, forKey: .workspaces))
        case "agentStatus":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .agentStatus(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                status: try payload.decode(AgentStatus.self, forKey: .status),
                title: try payload.decodeIfPresent(String.self, forKey: .title)
            )
        case "chatPage":
            self = .chatPage(try envelope.decode(ChatPage.self, forKey: .payload))
        case "chatAppend":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .chatAppend(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                items: try payload.decodeLossyArray(of: ChatItem.self, forKey: .items)
            )
        case "chatUpdate":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .chatUpdate(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                items: try payload.decodeLossyArray(of: ChatItem.self, forKey: .items)
            )
        case "chatMeta":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .chatMeta(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                meta: try payload.decode(ChatMeta.self, forKey: .meta)
            )
        case "pending":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .pending(requests: try payload.decodeLossyArray(of: PendingRequest.self, forKey: .requests))
        case "ack":
            let payload = try envelope.payloadIfPresent(keyedBy: PayloadKey.self)
            self = .ack(agentId: try payload?.decodeIfPresent(AgentID.self, forKey: .agentId))
        case "pong":
            self = .pong
        case "error":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .error(
                code: try payload.decode(ProtocolErrorCode.self, forKey: .code),
                message: try payload.decode(String.self, forKey: .message)
            )
        default:
            self = .unknown(type: type)
        }
    }

    func encodePayload(into envelope: inout KeyedEncodingContainer<EnvelopeCodingKey>) throws {
        switch self {
        case .helloOk(let helloOk):
            try envelope.encode(helloOk, forKey: .payload)
        case .tree(let workspaces), .treeChanged(let workspaces):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(workspaces, forKey: .workspaces)
        case .agentStatus(let agentId, let status, let title):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(status, forKey: .status)
            try payload.encodeIfPresent(title, forKey: .title)
        case .chatPage(let page):
            try envelope.encode(page, forKey: .payload)
        case .chatAppend(let agentId, let items), .chatUpdate(let agentId, let items):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(items, forKey: .items)
        case .chatMeta(let agentId, let meta):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(meta, forKey: .meta)
        case .pending(let requests):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(requests, forKey: .requests)
        case .ack(let agentId):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encodeIfPresent(agentId, forKey: .agentId)
        case .pong, .unknown:
            envelope.emptyPayload()
        case .error(let code, let message):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(code, forKey: .code)
            try payload.encode(message, forKey: .message)
        }
    }
}
