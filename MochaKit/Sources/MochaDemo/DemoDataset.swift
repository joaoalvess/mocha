import Foundation
import MochaProtocol

public enum DemoError: Error, Equatable, Sendable {
    case missingResource(String)
    case connectionClosed
}

struct DemoChat: Codable, Sendable {
    var agentId: AgentID
    var meta: ChatMeta
    var items: [ChatItem]
}

struct DemoDataset: Sendable {
    var workspaces: [WorkspaceNode]
    var chats: [DemoChat]

    private struct Tree: Codable {
        var workspaces: [WorkspaceNode]
    }

    static func bundled() throws -> DemoDataset {
        let decoder = JSONDecoder()
        guard let treeURL = Bundle.module.url(forResource: "tree", withExtension: "json") else {
            throw DemoError.missingResource("tree.json")
        }
        let tree = try decoder.decode(Tree.self, from: Data(contentsOf: treeURL))
        let chatURLs = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("chat-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !chatURLs.isEmpty else {
            throw DemoError.missingResource("chat-*.json")
        }
        let chats = try chatURLs.map { try decoder.decode(DemoChat.self, from: Data(contentsOf: $0)) }
        return DemoDataset(workspaces: tree.workspaces, chats: chats)
    }
}
