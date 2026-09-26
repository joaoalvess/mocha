import Foundation
import MochaHerdr
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite struct HerdrTreeBuilderTests {
    @Test func realSnapshotBuildsOrderedWorkspacesTabsAndAgents() throws {
        let state = try HerdrBridgeFixtures.state("session.snapshot.response.json")
        let git = HerdrGitSnapshot(
            branches: [
                "/Users/dev/Developer": "main",
                "/Users/dev/projects/demo-api": "main",
                "/Users/dev/projects/demo-api/.claude/worktrees/feature": "feature",
            ],
            dirtyDirectories: ["/Users/dev/projects/demo-api"]
        )
        let tree = HerdrTreeBuilder.build(state: state, git: git)
        #expect(tree.map(\.id) == ["wJ", "w17", "wY", "wW"])
        #expect(tree.map(\.number) == [1, 2, 3, 4])
        #expect(tree.allSatisfy { $0.children.isEmpty })

        let developer = tree[0]
        #expect(developer.label == "Developer")
        #expect(developer.repoName == nil)
        #expect(developer.branch == "main")
        #expect(!developer.isDirty)
        #expect(developer.agentStatus == .working)
        #expect(developer.tabs.map(\.id) == ["wJ:t7", "wJ:tE"])
        #expect(developer.tabs[1].title == "Caffeinate")
        #expect(developer.tabs[1].agents.isEmpty)
        let main = try #require(developer.tabs[0].agents.first)
        #expect(main.id == "wJ:p7")
        #expect(main.kind == "claude")
        #expect(main.status == .working)
        #expect(main.title == "tarefa principal")
        #expect(main.workspaceLabel == "Developer")
        #expect(main.sessionId == "11111111-1111-4111-8111-111111111111")
        #expect(main.model == nil)
        #expect(main.lastActivityAt == nil)
        #expect(main.pendingCount == 0)

        let api = tree[1]
        #expect(api.repoName == "demo-api")
        #expect(api.branch == "main")
        #expect(api.isDirty)
        #expect(api.agentStatus == .idle)
        let reviewer = try #require(api.tabs.first?.agents.first)
        #expect(reviewer.branch == "feature")
        #expect(reviewer.title == "revisão do código")

        #expect(tree[2].agentStatus == .unknown)
        #expect(tree[2].tabs.map(\.title) == ["fish"])
        #expect(tree[3].agentStatus == .unknown)
    }

    @Test func twoAgentsInOneTabBecomeTwoRowsAndStatusPrioritizesWork() throws {
        var state = try HerdrBridgeFixtures.state("session.snapshot.two-agents-one-tab.response.json")
        var tree = HerdrTreeBuilder.build(state: state, git: HerdrGitSnapshot())
        let tab = try #require(tree.first?.tabs.first)
        #expect(tab.agents.map(\.id) == ["w1A:p1", "w1A:p2"])
        #expect(tab.agents.map(\.sessionId) == ["53360f7b-12da-40ad-b37f-37b246ccfc35", "c31eceaf-ad1d-4b76-b947-380a7f8c668b"])
        #expect(tree.first?.agentStatus == .done)
        state.updatePane("w1A:p2") { $0.agentStatus = .working }
        tree = HerdrTreeBuilder.build(state: state, git: HerdrGitSnapshot())
        #expect(tree.first?.agentStatus == .working)
        state.updatePane("w1A:p1") { $0.agentStatus = .blocked }
        tree = HerdrTreeBuilder.build(state: state, git: HerdrGitSnapshot())
        #expect(tree.first?.agentStatus == .blocked)
    }

    @Test func linkedWorktreeIsNestedUnderTheMainWorkspaceOfTheSameRepo() throws {
        let state = try HerdrBridgeFixtures.state("session.snapshot.linked-worktree.synthetic.json")
        let git = HerdrGitSnapshot(
            branches: [
                "/Users/dev/projects/demo-app": "main",
                "/Users/dev/projects/demo-app/.claude/worktrees/feature-x": "feature-x",
            ],
            dirtyDirectories: ["/Users/dev/projects/demo-app/.claude/worktrees/feature-x"]
        )
        let tree = HerdrTreeBuilder.build(state: state, git: git)
        #expect(tree.map(\.id) == ["w5", "w7", "w8"])
        let main = tree[0]
        #expect(main.children.map(\.id) == ["w6"])
        #expect(main.repoName == "demo-app")
        #expect(main.branch == "main")
        #expect(!main.isDirty)
        #expect(main.agentStatus == .idle)
        let linked = main.children[0]
        #expect(linked.repoName == "demo-app")
        #expect(linked.branch == "feature-x")
        #expect(linked.isDirty)
        #expect(linked.agentStatus == .working)
        #expect(linked.children.isEmpty)
        let orphan = tree[2]
        #expect(orphan.children.isEmpty)
        #expect(orphan.repoName == "demo-web")
        #expect(orphan.agentStatus == .blocked)
        let codex = try #require(orphan.tabs.first?.agents.first)
        #expect(codex.kind == "codex")
        #expect(codex.sessionId == nil)
        let notes = tree[1]
        #expect(notes.repoName == nil)
        #expect(notes.agentStatus == .unknown)
        #expect(notes.tabs.first?.agents.isEmpty == true)
    }

    @Test func agentBranchComesFromTheForegroundDirectory() throws {
        let state = try HerdrBridgeFixtures.state("session.snapshot.linked-worktree.synthetic.json")
        let git = HerdrGitSnapshot(
            branches: [
                "/Users/dev/projects/demo-app": "main",
                "/Users/dev/projects/demo-app/.claude/worktrees/feature-x": "feature-x",
            ]
        )
        let tree = HerdrTreeBuilder.build(state: state, git: git)
        #expect(treeAgent("w5:p1", in: tree)?.branch == "main")
        #expect(treeAgent("w5:p3", in: tree)?.branch == "feature-x")
        #expect(treeWorkspace("w5", in: tree)?.branch == "main")
    }

    @Test func agentTitleFallsBackToTabLabelThenDefault() throws {
        var state = try HerdrBridgeFixtures.state("session.snapshot.linked-worktree.synthetic.json")
        #expect(treeAgent("w5:p3", in: HerdrTreeBuilder.build(state: state, git: HerdrGitSnapshot()))?.title == "claude")
        if let index = state.tabs.firstIndex(where: { $0.tabId == "w5:t2" }) {
            state.tabs[index].label = ""
        }
        #expect(treeAgent("w5:p3", in: HerdrTreeBuilder.build(state: state, git: HerdrGitSnapshot()))?.title == "Claude Code")
        #expect(treeAgent("w5:p1", in: HerdrTreeBuilder.build(state: state, git: HerdrGitSnapshot()))?.title == "tarefa principal")
    }

    @Test func workspaceDirectoryPrefersCheckoutPathThenActiveTabPane() throws {
        let state = try HerdrBridgeFixtures.state("session.snapshot.linked-worktree.synthetic.json")
        let directories = Dictionary(uniqueKeysWithValues: state.workspaces.map { ($0.workspaceId, HerdrTreeBuilder.workspaceDirectory($0, in: state)) })
        #expect(directories["w5"] == "/Users/dev/projects/demo-app")
        #expect(directories["w6"] == "/Users/dev/projects/demo-app/.claude/worktrees/feature-x")
        #expect(directories["w7"] == "/Users/dev/projects/notes")
        let real = try HerdrBridgeFixtures.state("session.snapshot.response.json")
        let developer = try #require(real.workspace("wJ"))
        #expect(HerdrTreeBuilder.workspaceDirectory(developer, in: real) == "/Users/dev/Developer")
    }

    @Test func aggregateFollowsPriority() {
        #expect(HerdrTreeBuilder.aggregateStatus([]) == .unknown)
        #expect(HerdrTreeBuilder.aggregateStatus([.unknown]) == .unknown)
        #expect(HerdrTreeBuilder.aggregateStatus([.idle, .unknown]) == .idle)
        #expect(HerdrTreeBuilder.aggregateStatus([.idle, .done]) == .done)
        #expect(HerdrTreeBuilder.aggregateStatus([.done, .working]) == .working)
        #expect(HerdrTreeBuilder.aggregateStatus([.working, .blocked, .idle]) == .blocked)
    }
}
