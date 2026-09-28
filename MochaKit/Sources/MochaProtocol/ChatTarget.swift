public enum ChatTarget: Sendable, Hashable {
    case agent(AgentID)
    case session(String)
    case codexThread(String)
    case subagent(sessionId: String, agentId: String)
}

extension KeyedDecodingContainer {
    func decodeChatTarget(agentIdKey: Key, sessionIdKey: Key, subagentIdKey: Key, providerKey: Key) throws -> ChatTarget {
        let agentId = try decodeIfPresent(AgentID.self, forKey: agentIdKey)
        let sessionId = try decodeIfPresent(String.self, forKey: sessionIdKey)
        let subagentId = try decodeIfPresent(String.self, forKey: subagentIdKey)
        let provider = try decodeIfPresent(AgentProvider.self, forKey: providerKey) ?? .claude
        switch (agentId, sessionId, subagentId) {
        case (let agentId?, nil, nil) where provider == .claude:
            return .agent(agentId)
        case (nil, let sessionId?, nil) where provider == .claude:
            return .session(sessionId)
        case (nil, let sessionId?, nil) where provider == .codex:
            return .codexThread(sessionId)
        case (nil, let sessionId?, let subagentId?) where provider == .claude:
            return .subagent(sessionId: sessionId, agentId: subagentId)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected exactly one of \(agentIdKey.stringValue) and \(sessionIdKey.stringValue), "
                        + "and \(subagentIdKey.stringValue) only with \(sessionIdKey.stringValue)"
                )
            )
        }
    }
}

extension KeyedEncodingContainer {
    mutating func encodeChatTarget(_ target: ChatTarget, agentIdKey: Key, sessionIdKey: Key, subagentIdKey: Key, providerKey: Key) throws {
        switch target {
        case .agent(let agentId):
            try encode(agentId, forKey: agentIdKey)
        case .session(let sessionId):
            try encode(sessionId, forKey: sessionIdKey)
        case .codexThread(let threadId):
            try encode(threadId, forKey: sessionIdKey)
            try encode(AgentProvider.codex, forKey: providerKey)
        case .subagent(let sessionId, let agentId):
            try encode(sessionId, forKey: sessionIdKey)
            try encode(agentId, forKey: subagentIdKey)
        }
    }
}
