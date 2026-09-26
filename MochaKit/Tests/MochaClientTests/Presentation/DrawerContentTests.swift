import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct DrawerContentTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func agent(
        _ id: AgentID,
        kind: String = "claude",
        status: AgentStatus = .idle,
        title: String,
        workspace: String,
        branch: String? = nil,
        minutesAgo: Double? = nil
    ) -> AgentSummary {
        AgentSummary(
            id: id,
            kind: kind,
            status: status,
            title: title,
            workspaceLabel: workspace,
            model: nil,
            branch: branch,
            sessionId: nil,
            lastActivityAt: minutesAgo.map { now.addingTimeInterval(-$0 * 60) },
            contextLeftPercent: nil
        )
    }

    static let workspaces: [WorkspaceNode] = [
        WorkspaceNode(
            id: "w1", label: "demo-app", number: 1, repoName: "demo-app", branch: "main", isDirty: true, agentStatus: .idle,
            tabs: [
                TabNode(id: "w1:t1", title: "Claude", agents: [
                    agent("w1:p1", title: "Testes e tela de ajustes", workspace: "demo-app", branch: "main", minutesAgo: 6),
                ]),
                TabNode(id: "w1:t2", title: "zsh", agents: []),
            ],
            children: [
                WorkspaceNode(
                    id: "w5", label: "login-social", number: 5, repoName: "demo-app", branch: "feat/login-social", isDirty: true,
                    agentStatus: .working,
                    tabs: [
                        TabNode(id: "w5:t1", title: "Claude", agents: [
                            agent("w5:p1", status: .working, title: "Login com a Apple", workspace: "login-social", branch: "feat/login-social", minutesAgo: 0.1),
                        ]),
                    ],
                    children: []
                ),
            ]
        ),
        WorkspaceNode(
            id: "w2", label: "site-pessoal", number: 2, repoName: "site-pessoal", branch: "main", isDirty: false, agentStatus: .blocked,
            tabs: [
                TabNode(id: "w2:t1", title: "Claude", agents: [
                    agent("w2:p1", status: .blocked, title: "Modo escuro e RSS", workspace: "site-pessoal", branch: "main", minutesAgo: 1),
                ]),
                TabNode(id: "w2:t2", title: "npm run dev", agents: []),
            ],
            children: []
        ),
        WorkspaceNode(
            id: "w3", label: "receitas-api", number: 3, repoName: "receitas-api", branch: "development", isDirty: false, agentStatus: .working,
            tabs: [
                TabNode(id: "w3:t1", title: "Claude", agents: [
                    agent("w3:p1", status: .working, title: "Paginação com cursor em /receitas", workspace: "receitas-api", branch: "development", minutesAgo: 2),
                ]),
                TabNode(id: "w3:t2", title: "revisão", agents: [
                    agent("w3:p2", title: "Sessão limpa", workspace: "receitas-api", branch: "feat/cursor", minutesAgo: 7),
                ]),
                TabNode(id: "w3:t3", title: "go run ./cmd/api", agents: []),
            ],
            children: []
        ),
        WorkspaceNode(
            id: "w4", label: "anotacoes", number: 4, repoName: nil, branch: nil, isDirty: false, agentStatus: .idle,
            tabs: [
                TabNode(id: "w4:t1", title: "zsh", agents: []),
                TabNode(id: "w4:t2", title: "Agente", agents: [
                    agent("w4:p3", kind: "codex", title: "node", workspace: "anotacoes"),
                ]),
                TabNode(id: "w4:t3", title: "Claude", agents: [
                    agent("w4:p2", title: "Resumo das anotações", workspace: "anotacoes"),
                ]),
            ],
            children: []
        ),
    ]

    static func ids(_ rows: [DrawerTreeRow]) -> [String] {
        rows.map(\.id)
    }

    @Test func fullTreeNestsWorktreesUnderTheirRepository() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "", collapsed: [])
        #expect(Self.ids(rows) == [
            "workspace:w1", "agent:w1:p1", "tab:w1:t2",
            "workspace:w5", "agent:w5:p1",
            "workspace:w2", "agent:w2:p1", "tab:w2:t2",
            "workspace:w3", "agent:w3:p1", "agent:w3:p2", "tab:w3:t3",
            "workspace:w4", "tab:w4:t1", "agent:w4:p3", "agent:w4:p2",
        ])
        guard case .workspace(let nested) = rows[3], case .agent(let nestedAgent) = rows[4] else {
            Issue.record("unexpected rows")
            return
        }
        #expect(nested.level == 1)
        #expect(nested.branch == "feat/login-social")
        #expect(nested.isDirty)
        #expect(nestedAgent.level == 1)
    }

    @Test func agentBranchAppearsOnlyWhenItDiffersFromTheWorkspace() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "", collapsed: [])
        let branches = rows.compactMap { row -> (AgentID, String?)? in
            guard case .agent(let agent) = row else { return nil }
            return (agent.agent.id, agent.branch)
        }
        #expect(branches.first { $0.0 == "w3:p2" }?.1 == "feat/cursor")
        #expect(branches.filter { $0.1 != nil }.count == 1)
    }

    @Test func nonClaudeAgentShowsItsKindAndDoesNotCountAsClaude() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "", collapsed: [])
        let codex = rows.compactMap { row -> DrawerAgentRow? in
            guard case .agent(let agent) = row, agent.agent.id == "w4:p3" else { return nil }
            return agent
        }.first
        #expect(codex?.title == "codex")
        #expect(codex?.isClaude == false)
    }

    @Test func collapsedWorkspaceHidesItsTabsAndWorktrees() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "", collapsed: ["w1", "w4"])
        #expect(Self.ids(rows) == [
            "workspace:w1",
            "workspace:w2", "agent:w2:p1", "tab:w2:t2",
            "workspace:w3", "agent:w3:p1", "agent:w3:p2", "tab:w3:t3",
            "workspace:w4",
        ])
        guard case .workspace(let collapsed) = rows[0] else {
            Issue.record("unexpected first row")
            return
        }
        #expect(!collapsed.isExpanded)
    }

    @Test func collapsedWorktreeKeepsItsHeaderUnderAnExpandedParent() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "", collapsed: ["w5"])
        #expect(Self.ids(rows).prefix(4) == ["workspace:w1", "agent:w1:p1", "tab:w1:t2", "workspace:w5"])
        #expect(!Self.ids(rows).contains("agent:w5:p1"))
    }

    @Test func workspaceMatchShowsItsWholeSubtree() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "RECEITAS", collapsed: [])
        #expect(Self.ids(rows) == ["workspace:w3", "agent:w3:p1", "agent:w3:p2", "tab:w3:t3"])
    }

    @Test func tabMatchKeepsOnlyMatchingTabsUnderTheirWorkspaces() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "zsh", collapsed: [])
        #expect(Self.ids(rows) == ["workspace:w1", "tab:w1:t2", "workspace:w4", "tab:w4:t1"])
    }

    @Test func tabTitleMatchKeepsTheAgentsOfThatTab() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "revisao", collapsed: [])
        #expect(Self.ids(rows) == ["workspace:w3", "agent:w3:p2"])
    }

    @Test func agentTitleMatchInsideAWorktreeKeepsTheParentHeader() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "apple", collapsed: ["w1", "w5"])
        #expect(Self.ids(rows) == ["workspace:w1", "workspace:w5", "agent:w5:p1"])
        let expanded = rows.compactMap { row -> Bool? in
            guard case .workspace(let workspace) = row else { return nil }
            return workspace.isExpanded
        }
        #expect(expanded == [true, true])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "paginacao", collapsed: [])
        #expect(Self.ids(rows) == ["workspace:w3", "agent:w3:p1"])
    }

    @Test func searchMatchesTheDisplayedNameOfOtherAgents() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "codex", collapsed: [])
        #expect(Self.ids(rows) == ["workspace:w4", "agent:w4:p3"])
    }

    @Test func blankQueryDoesNotFilter() {
        let rows = DrawerContent.treeRows(for: Self.workspaces, query: "  \n", collapsed: [])
        #expect(rows.count == 16)
    }

    @Test func searchWithoutMatchesReturnsNoRows() {
        #expect(DrawerContent.treeRows(for: Self.workspaces, query: "kubernetes", collapsed: []).isEmpty)
        #expect(DrawerContent.recentRows(for: Self.workspaces, query: "kubernetes").isEmpty)
    }

    @Test func recentsListOnlyClaudeAgentsByLastActivity() {
        let rows = DrawerContent.recentRows(for: Self.workspaces, query: "")
        #expect(rows.map(\.id) == ["w5:p1", "w2:p1", "w3:p1", "w1:p1", "w3:p2", "w4:p2"])
        #expect(rows.map(\.workspaceLabel) == ["login-social", "site-pessoal", "receitas-api", "demo-app", "receitas-api", "anotacoes"])
    }

    @Test func recentsFilterByWorkspaceTabAndTitle() {
        #expect(DrawerContent.recentRows(for: Self.workspaces, query: "site").map(\.id) == ["w2:p1"])
        #expect(DrawerContent.recentRows(for: Self.workspaces, query: "revisão").map(\.id) == ["w3:p2"])
        #expect(DrawerContent.recentRows(for: Self.workspaces, query: "tela de").map(\.id) == ["w1:p1"])
        #expect(DrawerContent.recentRows(for: Self.workspaces, query: "codex").isEmpty)
    }

    @Test func recentSubtitleJoinsWorkspaceStateAndTime() {
        let rows = DrawerContent.recentRows(for: Self.workspaces, query: "")
        let subtitles = rows.map { $0.subtitle(now: Self.now) }
        #expect(subtitles == [
            "login-social · trabalhando · agora",
            "site-pessoal · precisa de você · há 1 min",
            "receitas-api · trabalhando · há 2 min",
            "demo-app · há 6 min",
            "receitas-api · há 7 min",
            "anotacoes",
        ])
    }

    @Test func collapsedWorkspacesRoundTripThroughStorage() {
        let stored = DrawerContent.storedValue(forCollapsed: ["w4", "w1"])
        #expect(stored == "w1\nw4")
        #expect(DrawerContent.collapsedWorkspaces(from: stored) == ["w1", "w4"])
        #expect(DrawerContent.collapsedWorkspaces(from: "").isEmpty)
    }
}
