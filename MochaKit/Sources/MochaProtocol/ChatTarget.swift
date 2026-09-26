public enum ChatTarget: Sendable, Hashable {
    case agent(AgentID)
    case session(String)
}

extension KeyedDecodingContainer {
    func decodeChatTarget(agentIdKey: Key, sessionIdKey: Key) throws -> ChatTarget {
        let agentId = try decodeIfPresent(AgentID.self, forKey: agentIdKey)
        let sessionId = try decodeIfPresent(String.self, forKey: sessionIdKey)
        switch (agentId, sessionId) {
        case (let agentId?, nil):
            return .agent(agentId)
        case (nil, let sessionId?):
            return .session(sessionId)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected exactly one of \(agentIdKey.stringValue) and \(sessionIdKey.stringValue)"
                )
            )
        }
    }
}

extension KeyedEncodingContainer {
    mutating func encodeChatTarget(_ target: ChatTarget, agentIdKey: Key, sessionIdKey: Key) throws {
        switch target {
        case .agent(let agentId):
            try encode(agentId, forKey: agentIdKey)
        case .session(let sessionId):
            try encode(sessionId, forKey: sessionIdKey)
        }
    }
}
