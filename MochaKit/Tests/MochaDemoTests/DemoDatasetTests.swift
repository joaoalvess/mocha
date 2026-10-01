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

private let forbiddenNames = (ProcessInfo.processInfo.environment["MOCHA_FORBIDDEN_NAMES"] ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    .filter { !$0.isEmpty }

@Suite struct DemoDatasetTests {
    let dataset: DemoDataset

    init() throws {
        dataset = try DemoDataset.bundled()
    }

    @Test func treeFollowsTheDrawerOfTheMock() throws {
        #expect(dataset.workspaces.map(\.label) == ["demo-app", "site-pessoal", "receitas-api", "anotacoes"])
        #expect(dataset.workspaces.map(\.number) == dataset.workspaces.map(\.number).sorted())
        let parents = dataset.workspaces.filter { !$0.children.isEmpty }
        #expect(parents.map(\.label) == ["demo-app"])
        let worktree = try #require(parents.first?.children.first)
        #expect(worktree.label == "login-social")
        #expect(worktree.repoName == parents.first?.repoName)
        #expect(worktree.branch == "feat/login-social")
        let rows = { (workspace: WorkspaceNode) in
            workspace.tabs.map { $0.agents.first?.title ?? $0.title }
        }
        let workspaces = allNodes(dataset.workspaces)
        let byLabel = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.label, $0) })
        #expect(rows(try #require(byLabel["demo-app"])) == ["Testes e tela de ajustes", "zsh"])
        #expect(rows(try #require(byLabel["login-social"])) == ["Login com a Apple"])
        #expect(rows(try #require(byLabel["site-pessoal"])) == ["Modo escuro e RSS", "npm run dev"])
        #expect(rows(try #require(byLabel["receitas-api"])) == [
            "Paginação com cursor em /receitas", "Sessão limpa", "go run ./cmd/api", "psql", "Cache de /receitas", "Migrations de índice",
        ])
        #expect(workspaces.map(\.branch) == ["main", "feat/login-social", "main", "development", nil])
        #expect(workspaces.map(\.isDirty) == [true, true, false, false, false])
    }

    @Test func bundledChatsTogetherCoverEveryKind() {
        let everyKind: Set<String> = [
            "userPrompt", "slashCommand", "assistantText", "plan", "thinking", "toolCall", "subagent", "workflow", "turnFooter",
            "recap", "notice", "unsupported",
        ]
        let bundled = dataset.chats.filter { $0.agentId != DemoLongChat.agentId }
        #expect(bundled.count == 8)
        #expect(Set(bundled.flatMap { $0.items.map { kindName($0.kind) } }) == everyKind)
        for chat in bundled {
            #expect(Set(chat.items.map(\.id)).count == chat.items.count, "\(chat.agentId) repete ids")
            #expect(chat.items.map(\.at) == chat.items.map(\.at).sorted(), "\(chat.agentId) fora de ordem")
        }
        for agentId in ["w1:p1", "w2:p1"] {
            #expect((bundled.first { $0.agentId == agentId }?.items.count ?? 0) >= 100, "\(agentId)")
        }
    }

    @Test func archivedChatsHaveUniqueIdsInOrder() {
        #expect(dataset.sessionChats.count == 3)
        for chat in dataset.sessionChats {
            #expect(UUID(uuidString: chat.session.id) != nil)
            #expect(!chat.items.isEmpty)
            #expect(Set(chat.items.map(\.id)).count == chat.items.count)
            #expect(chat.items.map(\.at) == chat.items.map(\.at).sorted())
            #expect(chat.session.lastActivityAt == chat.items.last?.at)
            #expect(chat.session.sessionStartedAt == chat.items.first?.at)
        }
    }

    @Test func generatedChatHasTwoThousandVariedItems() throws {
        let chat = try #require(dataset.chats.first { $0.agentId == DemoLongChat.agentId })
        let items = chat.items
        #expect(items.count == 2_000)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.map(\.at) == items.map(\.at).sorted())
        #expect(Set(items.map(\.kind.type)) == [
            "userPrompt", "slashCommand", "assistantText", "thinking", "toolCall", "subagent", "turnFooter", "recap", "notice",
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

    @Test func generatedChatEndsWithTheWorkingTurnOfTheMock() throws {
        let items = DemoLongChat.items()
        let prompt = try #require(items.last { if case .userPrompt = $0.kind { true } else { false } })
        #expect(prompt.kind == .userPrompt(
            text: "procura os outros endpoints que ainda usam OFFSET e roda o teste de carga de /receitas em paralelo",
            imageCount: 0
        ))
        #expect(prompt.at == DemoDataset.anchor.addingTimeInterval(DemoLongChat.turnStartOffset))
        let turn = items.drop { $0.id != prompt.id }
        #expect(turn.map(\.kind.type) == [
            "userPrompt", "thinking", "assistantText", "subagent", "subagent", "toolCall", "assistantText", "toolCall", "toolCall",
            "toolCall",
        ])
        let running = try #require(turn.last?.toolCall)
        #expect(running.name == "Bash")
        #expect(running.summary == "go test ./internal/ingredients -run Cursor")
        #expect(running.status == .running)
        let previous = items[items.count - turn.count - 1]
        #expect(previous.at < prompt.at)
        #expect(previous.kind.type == "turnFooter")
    }

    @Test func generatedChatIsDeterministic() {
        #expect(DemoLongChat.items() == DemoLongChat.items())
    }

    @Test func everySupportedAgentInTheTreeHasAChatWithTheSameStatus() throws {
        let agents = dataset.workspaces.allAgents
        let supportedAgents = agents.filter { $0.kind == "claude" || $0.kind == "codex" }
        #expect(supportedAgents.count == dataset.chats.count)
        #expect(agents.contains { $0.kind != "claude" })
        for agent in supportedAgents {
            let chat = try #require(dataset.chats.first { $0.agentId == agent.id }, "\(agent.id) sem chat")
            #expect(chat.meta.status == agent.status)
            #expect(chat.meta.title == agent.title)
            #expect(chat.meta.workspaceLabel == agent.workspaceLabel)
            #expect(agent.lastActivityAt == chat.items.last?.at)
            #expect(agent.sessionStartedAt == chat.items.first?.at, "\(agent.id)")
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
        #expect(files.count == 9)
        var texts = try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        let generated = try JSONEncoder().encode(DemoLongChat.chat())
        texts.append(("chat gerado", String(decoding: generated, as: UTF8.self)))
        for subagent in DemoSubagents.all {
            let transcript = try JSONEncoder().encode(subagent.items)
            texts.append((subagent.description, String(decoding: transcript, as: UTF8.self)))
        }
        for (name, text) in texts {
            for forbidden in forbiddenNames {
                #expect(!text.lowercased().contains(forbidden), "\(name) contém \(forbidden)")
            }
        }
    }
}
