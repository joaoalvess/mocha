public struct HelloPayload: Codable, Sendable, Hashable {
    public var deviceToken: String?
    public var pairingCode: String?
    public var deviceName: String
    public var appVersion: String
    public var apns: ApnsRegistration?

    public init(
        deviceToken: String? = nil,
        pairingCode: String? = nil,
        deviceName: String,
        appVersion: String,
        apns: ApnsRegistration? = nil
    ) {
        self.deviceToken = deviceToken
        self.pairingCode = pairingCode
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.apns = apns
    }
}

public enum ClientMessage: Sendable, Hashable {
    case hello(HelloPayload)
    case openChat(target: ChatTarget, before: String? = nil, limit: Int? = nil)
    case closeChat(target: ChatTarget)
    case sendPrompt(agentId: AgentID, text: String)
    case interrupt(agentId: AgentID)
    case setForeground(agentId: AgentID?, isActive: Bool)
    case unpair
    case ping
    case archive(sessionId: String)
    case slash(agentId: AgentID, command: String)
    case setPreferences(DevicePreferences)
    case respond(requestId: RequestID, response: PendingResponse)
    case newAgentTab(workspaceId: WorkspaceID)
    case registerLiveActivity(LiveActivityRegistration)
    case unknown(type: String)

    public var type: String {
        switch self {
        case .hello: "hello"
        case .openChat: "openChat"
        case .closeChat: "closeChat"
        case .sendPrompt: "sendPrompt"
        case .interrupt: "interrupt"
        case .setForeground: "setForeground"
        case .unpair: "unpair"
        case .ping: "ping"
        case .archive: "archive"
        case .slash: "slash"
        case .setPreferences: "setPreferences"
        case .respond: "respond"
        case .newAgentTab: "newAgentTab"
        case .registerLiveActivity: "registerLiveActivity"
        case .unknown(let type): type
        }
    }
}

extension ClientMessage {
    private enum PayloadKey: String, CodingKey {
        case agentId, sessionId, before, limit, text, isActive, command, requestId, response, workspaceId
    }

    init(type: String, envelope: KeyedDecodingContainer<EnvelopeCodingKey>) throws {
        switch type {
        case "hello":
            self = .hello(try envelope.decode(HelloPayload.self, forKey: .payload))
        case "openChat":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .openChat(
                target: try payload.decodeChatTarget(agentIdKey: .agentId, sessionIdKey: .sessionId),
                before: try payload.decodeIfPresent(String.self, forKey: .before),
                limit: try payload.decodeIfPresent(Int.self, forKey: .limit)
            )
        case "closeChat":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .closeChat(target: try payload.decodeChatTarget(agentIdKey: .agentId, sessionIdKey: .sessionId))
        case "sendPrompt":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .sendPrompt(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                text: try payload.decode(String.self, forKey: .text)
            )
        case "interrupt":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .interrupt(agentId: try payload.decode(AgentID.self, forKey: .agentId))
        case "setForeground":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .setForeground(
                agentId: try payload.decodeIfPresent(AgentID.self, forKey: .agentId),
                isActive: try payload.decode(Bool.self, forKey: .isActive)
            )
        case "unpair":
            self = .unpair
        case "ping":
            self = .ping
        case "archive":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .archive(sessionId: try payload.decode(String.self, forKey: .sessionId))
        case "slash":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .slash(
                agentId: try payload.decode(AgentID.self, forKey: .agentId),
                command: try payload.decode(String.self, forKey: .command)
            )
        case "setPreferences":
            self = .setPreferences(try envelope.decode(DevicePreferences.self, forKey: .payload))
        case "respond":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .respond(
                requestId: try payload.decode(RequestID.self, forKey: .requestId),
                response: try payload.decode(PendingResponse.self, forKey: .response)
            )
        case "newAgentTab":
            let payload = try envelope.payload(keyedBy: PayloadKey.self)
            self = .newAgentTab(workspaceId: try payload.decode(WorkspaceID.self, forKey: .workspaceId))
        case "registerLiveActivity":
            self = .registerLiveActivity(try envelope.decode(LiveActivityRegistration.self, forKey: .payload))
        default:
            self = .unknown(type: type)
        }
    }

    func encodePayload(into envelope: inout KeyedEncodingContainer<EnvelopeCodingKey>) throws {
        switch self {
        case .hello(let hello):
            try envelope.encode(hello, forKey: .payload)
        case .openChat(let target, let before, let limit):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encodeChatTarget(target, agentIdKey: .agentId, sessionIdKey: .sessionId)
            try payload.encodeIfPresent(before, forKey: .before)
            try payload.encodeIfPresent(limit, forKey: .limit)
        case .closeChat(let target):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encodeChatTarget(target, agentIdKey: .agentId, sessionIdKey: .sessionId)
        case .interrupt(let agentId):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
        case .sendPrompt(let agentId, let text):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(text, forKey: .text)
        case .setForeground(let agentId, let isActive):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encodeIfPresent(agentId, forKey: .agentId)
            try payload.encode(isActive, forKey: .isActive)
        case .unpair, .ping, .unknown:
            envelope.emptyPayload()
        case .archive(let sessionId):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(sessionId, forKey: .sessionId)
        case .slash(let agentId, let command):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(agentId, forKey: .agentId)
            try payload.encode(command, forKey: .command)
        case .setPreferences(let preferences):
            try envelope.encode(preferences, forKey: .payload)
        case .respond(let requestId, let response):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(requestId, forKey: .requestId)
            try payload.encode(response, forKey: .response)
        case .newAgentTab(let workspaceId):
            var payload = envelope.nestedContainer(keyedBy: PayloadKey.self, forKey: .payload)
            try payload.encode(workspaceId, forKey: .workspaceId)
        case .registerLiveActivity(let registration):
            try envelope.encode(registration, forKey: .payload)
        }
    }
}
