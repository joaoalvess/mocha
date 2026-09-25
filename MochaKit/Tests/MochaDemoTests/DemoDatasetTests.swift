import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

private func kindName(_ kind: ChatItemKind) -> String {
    if case .unsupported = kind {
        return "unsupported"
    }
    return kind.type
}

private func allNodes(_ workspaces: [WorkspaceNode]) -> [WorkspaceNode] {
    workspaces.flatMap { [$0] + allNodes($0.children) }
}

@Suite struct DemoDatasetTests {
    let dataset: DemoDataset

    init() throws {
        dataset = try DemoDataset.bundled()
    }

    @Test func treeHasFourWorkspacesAndOneNestedWorktree() {
        #expect(dataset.workspaces.count == 4)
        let parents = dataset.workspaces.filter { !$0.children.isEmpty }
        #expect(parents.count == 1)
        #expect(parents.first?.children.first?.repoName == parents.first?.repoName)
        #expect(dataset.workspaces.map(\.number) == dataset.workspaces.map(\.number).sorted())
    }

    @Test func thereAreThreeLongChatsCoveringEveryKind() {
        let everyKind: Set<String> = [
            "userPrompt", "slashCommand", "assistantText", "thinking", "toolCall", "turnFooter", "recap", "notice",
            "unsupported",
        ]
        #expect(dataset.chats.count == 3)
        for chat in dataset.chats {
            #expect(chat.items.count >= 100, "\(chat.agentId) tem \(chat.items.count) itens")
            #expect(Set(chat.items.map { kindName($0.kind) }) == everyKind, "\(chat.agentId)")
            #expect(Set(chat.items.map(\.id)).count == chat.items.count, "\(chat.agentId) repete ids")
            #expect(chat.items.map(\.at) == chat.items.map(\.at).sorted(), "\(chat.agentId) fora de ordem")
        }
    }

    @Test func everyClaudeAgentInTheTreeHasAChatWithTheSameStatus() throws {
        let agents = allNodes(dataset.workspaces).flatMap(\.tabs).flatMap(\.agents)
        let claudeAgents = agents.filter { $0.kind == "claude" }
        #expect(claudeAgents.count == dataset.chats.count)
        #expect(agents.contains { $0.kind != "claude" })
        for agent in claudeAgents {
            let chat = try #require(dataset.chats.first { $0.agentId == agent.id }, "\(agent.id) sem chat")
            #expect(chat.meta.status == agent.status)
            #expect(chat.meta.title == agent.title)
            #expect(chat.meta.workspaceLabel == agent.workspaceLabel)
            #expect(agent.lastActivityAt == chat.items.last?.at)
        }
    }

    @Test func demoContentUsesOnlyNeutralNames() throws {
        let resources = Fixtures.root
            .deletingLastPathComponent()
            .appending(path: "Sources/MochaDemo/Resources", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
        #expect(files.count == 4)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8).lowercased()
            for forbidden in ["initech", "acme", "globex", "bank-app"] {
                #expect(!text.contains(forbidden), "\(file.lastPathComponent) contém \(forbidden)")
            }
        }
    }
}
