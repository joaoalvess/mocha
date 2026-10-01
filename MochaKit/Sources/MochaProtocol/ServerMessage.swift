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
    public static let sessionNotFound = ProtocolErrorCode(rawValue: "sessionNotFound")
    public static let agentBlocked = ProtocolErrorCode(rawValue: "agentBlocked")
    public static let requestNotFound = ProtocolErrorCode(rawValue: "requestNotFound")
    public static let herdrUnavailable = ProtocolErrorCode(rawValue: "herdrUnavailable")
    public static let codexUnavailable = ProtocolErrorCode(rawValue: "codexUnavailable")
    public static let modeUnavailable = ProtocolErrorCode(rawValue: "modeUnavailable")
    public static let screenBusy = ProtocolErrorCode(rawValue: "screenBusy")
    public static let `internal` = ProtocolErrorCode(rawValue: "internal")
}

public enum ServerMessage: Sendable, Hashable {
    case helloOk(HelloOkPayload)
    case tree(workspaces: [WorkspaceNode])
    case archived(sessions: [ArchivedSession])
    case usage(UsageSnapshot)
    case herdrStatus(connected: Bool)
    case treeChanged(workspaces: [WorkspaceNode])
    case agentStatus(agentId: AgentID, status: AgentStatus, title: String? = nil)
    case chatPage(ChatPage)
    case subagentList(agentId: AgentID, items: [SubagentSummary])
    case models(agentId: AgentID, options: [ModelOption])
    case webServers(host: String, servers: [WebServer])
    case chatAppend(target: ChatTarget, items: [ChatItem])
    case chatUpdate(target: ChatTarget, items: [ChatItem])
    case chatMeta(target: ChatTarget, meta: ChatMeta)
    case pending(requests: [PendingRequest])
    case ack(agentId: AgentID? = nil)
    case pong
    case error(code: ProtocolErrorCode, message: String)
    case unknown(type: String)

    public var type: String {
        switch self {
        case .helloOk: "helloOk"
        case .tree: "tree"
        case .archived: "archived"
        case .usage: "usage"
        case .herdrStatus: "herdrStatus"
        case .treeChanged: "treeChanged"
        case .agentStatus: "agentStatus"
        case .chatPage: "chatPage"
        case .subagentList: "subagentList"
        case .models: "models"
        case .webServers: "webServers"
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
        case workspaces, sessions, connected, agentId, sessionId, subagentId, provider, status, title, items, meta, requests, code, message, host, servers, options
    }

    init(type: String, envelope: KeyedDecodingContainer<EnvelopeCodingKey>) throws {
        switch type {
        case "helloOk":
            self = .helloOk(try envelope.decode(HelloOkPayload.self, forKey: .payload))
        case "tree":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .tree(workspaces: try payload.decode([WorkspaceNode].self, forKey: .workspaces))
        case "archived":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .archived(sessions: try payload.decodeLossyArray(of: ArchivedSession.self, forKey: .sessions))
        case "usage":
            self = .usage(try envelope.decode(UsageSnapshot.self, forKey: .payload))
        case "herdrStatus":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .herdrStatus(connected: try payload.decode(Bool.self, forKey: .connected))
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
        case "subagentList":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .subagentList(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                items: try payload.decodeLossyArray(of: SubagentSummary.self, forKey: .items)
            )
        case "models":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .models(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                options: try payload.decodeLossyArray(of: ModelOption.self, forKey: .options)
            )
        case "webServers":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .webServers(
                host: try payload.decode(String.self, forKey: .host),
                servers: try payload.decodeLossyArray(of: WebServer.self, forKey: .servers)
            )
        case "chatAppend":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .chatAppend(
                target: try payload.decodeChatTarget(agentIdKey: .agentId, sessionIdKey: .sessionId, subagentIdKey: .subagentId, providerKey: .provider),
                items: try payload.decodeLossyArray(of: ChatItem.self, forKey: .items)
            )
        case "chatUpdate":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .chatUpdate(
                target: try payload.decodeChatTarget(agentIdKey: .agentId, sessionIdKey: .sessionId, subagentIdKey: .subagentId, providerKey: .provider),
                items: try payload.decodeLossyArray(of: ChatItem.self, forKey: .items)
            )
        case "chatMeta":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .chatMeta(
                target: try payload.decodeChatTarget(agentIdKey: .agentId, sessionIdKey: .sessionId, subagentIdKey: .subagentId, providerKey: .provider),
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
        case .archived(let sessions):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(sessions, forKey: .sessions)
        case .usage(let snapshot):
            try envelope.encode(snapshot, forKey: .payload)
        case .herdrStatus(let connected):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(connected, forKey: .connected)
        case .agentStatus(let agentId, let status, let title):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(status, forKey: .status)
            try payload.encodeIfPresent(title, forKey: .title)
        case .chatPage(let page):
            try envelope.encode(page, forKey: .payload)
        case .subagentList(let agentId, let items):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(items, forKey: .items)
        case .models(let agentId, let options):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(options, forKey: .options)
        case .webServers(let host, let servers):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(host, forKey: .host)
            try payload.encode(servers, forKey: .servers)
        case .chatAppend(let target, let items), .chatUpdate(let target, let items):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encodeChatTarget(target, agentIdKey: .agentId, sessionIdKey: .sessionId, subagentIdKey: .subagentId, providerKey: .provider)
            try payload.encode(items, forKey: .items)
        case .chatMeta(let target, let meta):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encodeChatTarget(target, agentIdKey: .agentId, sessionIdKey: .sessionId, subagentIdKey: .subagentId, providerKey: .provider)
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
