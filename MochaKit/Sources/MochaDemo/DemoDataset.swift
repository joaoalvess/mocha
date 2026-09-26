import Foundation
import MochaProtocol

public enum DemoError: Error, Equatable, Sendable {
    case missingResource(String)
}

struct DemoChat: Codable, Sendable {
    var agentId: AgentID
    var meta: ChatMeta
    var items: [ChatItem]

    func shifted(by interval: TimeInterval) -> DemoChat {
        DemoChat(agentId: agentId, meta: meta, items: items.map { $0.shifted(by: interval) })
    }
}

struct DemoSessionChat: Codable, Sendable {
    var session: ArchivedSession
    var items: [ChatItem]

    var meta: ChatMeta {
        ChatMeta(
            title: session.title,
            workspaceLabel: session.workspaceLabel,
            model: session.model,
            branch: session.branch,
            status: .idle
        )
    }

    func shifted(by interval: TimeInterval) -> DemoSessionChat {
        DemoSessionChat(session: session.shifted(by: interval), items: items.map { $0.shifted(by: interval) })
    }
}

struct DemoDataset: Sendable {
    static let anchor = Date(timeIntervalSince1970: 1_790_337_600)

    var workspaces: [WorkspaceNode]
    var chats: [DemoChat]
    var sessionChats: [DemoSessionChat]
    var usage: UsageSnapshot

    var archived: [ArchivedSession] {
        sessionChats.map(\.session).sortedByRecency()
    }

    private struct Tree: Codable {
        var workspaces: [WorkspaceNode]
    }

    private struct Archived: Codable {
        var chats: [DemoSessionChat]
    }

    private struct Usage: Codable {
        var populated: UsageSnapshot
        var empty: UsageSnapshot
    }

    static func bundled(now: Date = Date(), isEmpty: Bool = false) throws -> DemoDataset {
        let tree = try decodeResource(Tree.self, named: "tree")
        let archived = try decodeResource(Archived.self, named: "archived")
        let usage = try decodeResource(Usage.self, named: "usage")
        let chatURLs = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("chat-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !chatURLs.isEmpty else {
            throw DemoError.missingResource("chat-*.json")
        }
        let decoder = JSONDecoder()
        let chats = try chatURLs.map { try decoder.decode(DemoChat.self, from: Data(contentsOf: $0)) }
        var dataset = DemoDataset(workspaces: tree.workspaces, chats: chats, sessionChats: archived.chats, usage: usage.populated)
        try dataset.addLongChat()
        if isEmpty {
            dataset = dataset.withoutClaude(usage: usage.empty)
        }
        return dataset.shifted(by: now.timeIntervalSince(anchor))
    }

    private static func decodeResource<Value: Decodable>(_ type: Value.Type, named name: String) throws -> Value {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw DemoError.missingResource("\(name).json")
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private mutating func addLongChat() throws {
        let chat = DemoLongChat.chat()
        let lastFooter = chat.items.last { if case .turnFooter = $0.kind { true } else { false } }
        let added = workspaces.updateAgent(withId: DemoLongChat.agentId) { agent in
            agent.sessionStartedAt = chat.items.first?.at
            agent.turnEndedAt = lastFooter?.at
        }
        guard added else {
            throw DemoError.missingResource("agente \(DemoLongChat.agentId)")
        }
        chats.append(chat)
    }

    private func withoutClaude(usage: UsageSnapshot) -> DemoDataset {
        DemoDataset(workspaces: workspaces.map { $0.withoutClaude() }, chats: [], sessionChats: [], usage: usage)
    }

    private func shifted(by interval: TimeInterval) -> DemoDataset {
        DemoDataset(
            workspaces: workspaces.map { $0.shifted(by: interval) },
            chats: chats.map { $0.shifted(by: interval) },
            sessionChats: sessionChats.map { $0.shifted(by: interval) },
            usage: usage.shifted(by: interval)
        )
    }
}

extension [ArchivedSession] {
    func sortedByRecency() -> [ArchivedSession] {
        sorted { ($0.lastActivityAt ?? $0.endedAt) > ($1.lastActivityAt ?? $1.endedAt) }
    }
}
