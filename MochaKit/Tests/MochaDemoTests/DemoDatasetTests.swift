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

private let forbiddenNames = ["initech", "acme", "globex", "bank-app"]

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

    @Test func thereAreThreeBundledLongChatsCoveringEveryKind() {
        let everyKind: Set<String> = [
            "userPrompt", "slashCommand", "assistantText", "thinking", "toolCall", "turnFooter", "recap", "notice",
            "unsupported",
        ]
        let bundled = dataset.chats.filter { $0.agentId != DemoLongChat.agentId }
        #expect(bundled.count == 3)
        for chat in bundled {
            #expect(chat.items.count >= 100, "\(chat.agentId) tem \(chat.items.count) itens")
            #expect(Set(chat.items.map { kindName($0.kind) }) == everyKind, "\(chat.agentId)")
            #expect(Set(chat.items.map(\.id)).count == chat.items.count, "\(chat.agentId) repete ids")
            #expect(chat.items.map(\.at) == chat.items.map(\.at).sorted(), "\(chat.agentId) fora de ordem")
        }
    }

    @Test func generatedChatHasTwoThousandVariedItems() throws {
        let chat = try #require(dataset.chats.first { $0.agentId == DemoLongChat.agentId })
        let items = chat.items
        #expect(items.count == 2_000)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.map(\.at) == items.map(\.at).sorted())
        #expect(Set(items.map(\.kind.type)) == [
            "userPrompt", "slashCommand", "assistantText", "thinking", "toolCall", "turnFooter", "recap", "notice",
        ])
        let toolCalls = items.compactMap(\.toolCall)
        #expect(Set(toolCalls.map(\.name)).count >= 8)
        #expect(Set(toolCalls.map(\.status)) == [.running, .succeeded, .failed])
        #expect(Set(toolCalls.map(\.toolUseId)).count == toolCalls.count)
        for toolCall in toolCalls {
            #expect((try? JSONSerialization.jsonObject(with: Data(toolCall.inputJSON.utf8))) != nil, "\(toolCall.inputJSON)")
        }
        let markdown = items.compactMap { item -> String? in
            guard case .assistantText(let markdown) = item.kind else { return nil }
            return markdown
        }
        for marker in ["## ", "```go", "```bash", "```json", "```sql", "| ", "> ", "- [x]", "1. ", "**", "*UTC*", "](", "---"] {
            #expect(markdown.contains { $0.contains(marker) }, "sem \(marker)")
        }
        #expect(items.contains { $0.kind == .thinking(text: nil) })
        #expect(items.contains { if case .thinking(.some) = $0.kind { true } else { false } })
    }

    @Test func generatedChatIsDeterministic() {
        #expect(DemoLongChat.items() == DemoLongChat.items())
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

    @Test func workspaceStatusIsTheAggregateOfItsOwnAgents() {
        for workspace in allNodes(dataset.workspaces) {
            #expect(workspace.agentStatus == workspace.aggregatedAgentStatus, "\(workspace.id)")
        }
    }

    @Test func demoContentUsesOnlyNeutralNames() throws {
        let resources = Fixtures.root
            .deletingLastPathComponent()
            .appending(path: "Sources/MochaDemo/Resources", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
        #expect(files.count == 4)
        var texts = try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        let generated = try JSONEncoder().encode(DemoLongChat.chat())
        texts.append(("chat gerado", String(decoding: generated, as: UTF8.self)))
        for (name, text) in texts {
            for forbidden in forbiddenNames {
                #expect(!text.lowercased().contains(forbidden), "\(name) contém \(forbidden)")
            }
        }
    }
}
