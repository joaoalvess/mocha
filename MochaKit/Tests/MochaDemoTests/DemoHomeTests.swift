import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

private enum HomeSection: Equatable {
    case needsYou, working, archived, done
}

private func section(of agent: AgentSummary, at now: Date) -> HomeSection {
    switch agent.status {
    case .blocked: return .needsYou
    case .working: return .working
    default: break
    }
    if agent.archivedAt != nil {
        return .archived
    }
    if let started = agent.sessionStartedAt, now.timeIntervalSince(started) > 6 * 3_600 {
        return .archived
    }
    if let last = agent.turnEndedAt ?? agent.lastActivityAt, now.timeIntervalSince(last) >= 10 * 60 {
        return .archived
    }
    return .done
}

private func age(_ date: Date?, at now: Date) throws -> TimeInterval {
    now.timeIntervalSince(try #require(date))
}

@Suite struct DemoHomeTests {
    let launch = Date(timeIntervalSince1970: 1_800_000_000)
    let dataset: DemoDataset

    init() throws {
        dataset = try DemoDataset.bundled(now: launch)
    }

    private func agent(_ id: AgentID) throws -> AgentSummary {
        try #require(dataset.workspaces.agent(withId: id))
    }

    @Test func timesAreRelativeToTheLaunch() throws {
        let later = try DemoDataset.bundled(now: launch.addingTimeInterval(3_600))
        let agentNow = try agent("w5:p1")
        let agentLater = try #require(later.workspaces.agent(withId: "w5:p1"))
        #expect(try age(agentNow.lastActivityAt, at: launch) == 5)
        #expect(try #require(agentLater.lastActivityAt).timeIntervalSince(try #require(agentNow.lastActivityAt)) == 3_600)
        #expect(later.usage.fetchedAt.timeIntervalSince(dataset.usage.fetchedAt) == 3_600)
        let firstLater = try #require(later.chats.first?.items.first?.at)
        let firstNow = try #require(dataset.chats.first?.items.first?.at)
        #expect(abs(firstLater.timeIntervalSince(firstNow) - 3_600) < 0.001)
    }

    @Test func claudeAgentsFillTheFourSectionsOfTheHomeLikeTheMock() throws {
        let claude = dataset.workspaces.allAgents.filter { $0.kind == "claude" }
        let sections = Dictionary(uniqueKeysWithValues: claude.map { ($0.id, section(of: $0, at: launch)) })
        #expect(sections == [
            "w2:p1": .needsYou,
            "w5:p1": .working,
            "w3:p1": .working,
            "w1:p1": .done,
            "w3:p2": .done,
            "w4:p2": .archived,
        ])
        let done = claude.filter { sections[$0.id] == .done }
            .sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
        #expect(done.map(\.id) == ["w1:p1", "w3:p2"])
    }

    @Test(arguments: [
        ("w2:p1", 58, 60.0, 120.0),
        ("w5:p1", 71, 0, 60),
        ("w3:p1", 84, 120, 180),
        ("w1:p1", 62, 360, 420),
        ("w3:p2", 100, 420, 480),
    ] as [(AgentID, Int, TimeInterval, TimeInterval)])
    func cardsHaveTheContextAndTheRelativeTimeOfTheMock(id: AgentID, context: Int, from: TimeInterval, to: TimeInterval) throws {
        let agent = try agent(id)
        #expect(agent.contextLeftPercent == context)
        let age = try age(agent.lastActivityAt, at: launch)
        #expect(age >= from && age < to, "\(id): \(age) s")
        #expect(agent.sessionStartedAt != nil)
    }

    @Test func cardTextsFollowTheMock() throws {
        let blocked = try agent("w2:p1")
        #expect(blocked.preview == MessagePreview(author: .assistant, text: "Posso rodar npm run build para validar o feed RSS antes do commit?"))
        #expect(blocked.activity == ToolActivity(toolName: "Bash", summary: "npm run build", status: .running))

        let login = try agent("w5:p1")
        #expect(login.preview == MessagePreview(
            author: .user,
            text: "implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain"
        ))
        #expect(login.activity == ToolActivity(toolName: "Bash", summary: "swift test --filter AppleSignIn", status: .running))
        #expect(login.turnStartedAt != nil)

        let receitas = try agent("w3:p1")
        #expect(receitas.preview?.author == .assistant)
        #expect(receitas.preview?.text.hasPrefix("Troquei o OFFSET por cursor em ListRecipes") == true)
        #expect(receitas.activity == nil)
        #expect(try age(receitas.turnStartedAt, at: launch) == 238)
        #expect(try age(receitas.sessionStartedAt, at: launch) > 6 * 3_600)

        let demoApp = try agent("w1:p1")
        #expect(demoApp.preview == MessagePreview(author: .assistant, text: "Os testes da tela de ajustes passaram. Quer que eu abra o PR?"))
        #expect(demoApp.turnEndedAt == demoApp.lastActivityAt)
        #expect(try age(demoApp.sessionStartedAt, at: launch) < 6 * 3_600)

        let clean = try agent("w3:p2")
        #expect(clean.title == "Sessão limpa")
        #expect(clean.preview == nil)
        #expect(clean.activity == nil)

        let stale = try agent("w4:p2")
        #expect(try age(stale.lastActivityAt, at: launch) >= 3 * 86_400)
        #expect(stale.turnEndedAt != nil)
        #expect(stale.preview?.author == .assistant)

        #expect(dataset.workspaces.allAgents.allSatisfy { $0.archivedAt == nil && $0.pendingCount == 0 })
    }

    @Test func previewsMatchTheChatsWhereTheMockAgrees() throws {
        for id in ["w1:p1", "w2:p1", "w3:p1", "w3:p2", "w4:p2"] {
            let items = try #require(dataset.chats.first { $0.agentId == id }?.items)
            var derived = try agent(id)
            derived.refreshHomeFields(from: items)
            #expect(derived.preview == (try agent(id)).preview, "\(id)")
        }
    }

    @Test func archivedSessionsAreOneClearedAndOneEndedFromYesterday() throws {
        let sessions = dataset.archived
        #expect(sessions.map(\.reason) == [.cleared, .ended])
        #expect(sessions.map(\.workspaceLabel) == ["login-social", "demo-app"])
        #expect(sessions.map(\.contextLeftPercent) == [47, 90])
        #expect(sessions.map { $0.preview?.text } == [
            "cria o worktree login-social a partir da main", "revisa o README antes do release",
        ])
        #expect(sessions.allSatisfy { $0.preview?.author == .user })
        for session in sessions {
            let age = try age(session.lastActivityAt, at: launch)
            #expect(age >= 86_400 && age < 2 * 86_400)
        }
        let cleared = try #require(sessions.first)
        #expect(cleared.agentId == "w5:p1")
        #expect(cleared.endedAt == (try agent("w5:p1")).sessionStartedAt)
    }

    @Test func usageFollowsTheUsageSheet() throws {
        let usage = dataset.usage
        #expect(usage.plan == "Max 20x")
        #expect(usage.account == "d•••@e•••.com")
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(usage.windows.map(\.usedPercent) == [12, 71])
        let fiveHour = try #require(usage.windows[0].resetsAt).timeIntervalSince(launch)
        let weekly = try #require(usage.windows[1].resetsAt).timeIntervalSince(launch)
        #expect(fiveHour > 3 * 3_600 + 35 * 60 && fiveHour < 3 * 3_600 + 36 * 60)
        #expect(weekly > 2 * 86_400 + 10 * 3_600 && weekly < 2 * 86_400 + 11 * 3_600)
        let fetched = try age(usage.fetchedAt, at: launch)
        #expect(fetched >= 4 * 60 && fetched < 5 * 60)
    }

    @Test func emptyDatasetHasNoClaudeNoArchivedSessionsAndItsOwnUsage() throws {
        let empty = try DemoDataset.bundled(now: launch, isEmpty: true)
        #expect(empty.workspaces.map(\.id) == dataset.workspaces.map(\.id))
        #expect(!empty.workspaces.allAgents.contains { $0.kind == "claude" })
        #expect(empty.workspaces.allAgents.contains { $0.kind == "codex" })
        #expect(empty.chats.isEmpty)
        #expect(empty.archived.isEmpty)
        #expect(empty.usage.windows.map(\.usedPercent) == [3, 64])
        let loginSocial = try #require(empty.workspaces.first?.children.first)
        #expect(loginSocial.tabs.map(\.title) == ["zsh"])
        #expect(loginSocial.agentStatus == .unknown)
    }

    @Test(arguments: [
        ("Troquei o `OFFSET` por cursor em `ListRecipes`.", "Troquei o OFFSET por cursor em ListRecipes."),
        ("## Resumo\n\n- **feito**\n- [x] testes\n> nota *importante*", "Resumo feito testes nota importante"),
        ("Veja [a doc](https://example.com) e\n\n```go\nfunc main() {}\n```", "Veja a doc e func main() {}"),
        ("1. um\n2. dois", "um dois"),
    ])
    func plainTextPreviewStripsMarkdown(markdown: String, expected: String) {
        #expect(DemoPlainText.preview(fromMarkdown: markdown) == expected)
    }

    @Test func plainTextPreviewIsCutAtTwoHundredCharacters() {
        let preview = DemoPlainText.preview(fromMarkdown: String(repeating: "a ", count: 300))
        #expect(preview.count == 200)
    }

    @Test func imageOnlyPromptPreviewsAsImage() {
        let item = ChatItem(id: "i", at: launch, kind: .userPrompt(text: "", imageCount: 2))
        #expect(item.messagePreview == MessagePreview(author: .user, text: "[imagem]"))
    }
}
