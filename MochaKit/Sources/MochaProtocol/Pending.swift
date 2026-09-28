import Foundation

public enum PendingKind: Codable, Sendable, Hashable {
    case permission(toolName: String, summary: String, inputJSON: String)
    case question(questions: [PendingQuestion])

    public var type: String {
        switch self {
        case .permission: "permission"
        case .question: "question"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolName, summary, inputJSON, questions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "permission":
            self = .permission(
                toolName: try container.decode(String.self, forKey: .toolName),
                summary: try container.decode(String.self, forKey: .summary),
                inputJSON: try container.decode(String.self, forKey: .inputJSON)
            )
        case "question":
            self = .question(questions: try container.decode([PendingQuestion].self, forKey: .questions))
        default:
            throw unknownTypeError(type, in: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .permission(let toolName, let summary, let inputJSON):
            try container.encode(toolName, forKey: .toolName)
            try container.encode(summary, forKey: .summary)
            try container.encode(inputJSON, forKey: .inputJSON)
        case .question(let questions):
            try container.encode(questions, forKey: .questions)
        }
    }
}

public struct PendingQuestion: Codable, Sendable, Hashable {
    public var id: String?
    public var header: String
    public var question: String
    public var options: [PendingOption]
    public var multiSelect: Bool

    public init(header: String, question: String, options: [PendingOption], multiSelect: Bool, id: String? = nil) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
    }
}

public struct PendingOption: Codable, Sendable, Hashable {
    public var label: String
    public var description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

public struct PendingRequest: Codable, Sendable, Hashable, Identifiable {
    public var id: RequestID
    public var agentId: AgentID
    public var createdAt: Date
    public var kind: PendingKind

    public init(id: RequestID, agentId: AgentID, createdAt: Date, kind: PendingKind) {
        self.id = id
        self.agentId = agentId
        self.createdAt = createdAt
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, agentId, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RequestID.self, forKey: .id)
        agentId = try container.decode(AgentID.self, forKey: .agentId)
        createdAt = try container.decodeProtocolDate(forKey: .createdAt)
        kind = try PendingKind(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(agentId, forKey: .agentId)
        try container.encodeProtocolDate(createdAt, forKey: .createdAt)
        try kind.encode(to: encoder)
    }
}

public enum PendingResponse: Codable, Sendable, Hashable {
    case allow
    case deny(reason: String?)
    case answers([String: [String]])

    public var type: String {
        switch self {
        case .allow: "allow"
        case .deny: "deny"
        case .answers: "answers"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, reason, answers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "allow":
            self = .allow
        case "deny":
            self = .deny(reason: try container.decodeIfPresent(String.self, forKey: .reason))
        case "answers":
            self = .answers(try container.decode([String: [String]].self, forKey: .answers))
        default:
            throw unknownTypeError(type, in: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch self {
        case .allow:
            break
        case .deny(let reason):
            try container.encodeIfPresent(reason, forKey: .reason)
        case .answers(let answers):
            try container.encode(answers, forKey: .answers)
        }
    }
}
