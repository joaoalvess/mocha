import MochaProtocol
import Testing
@testable import MochaDaemonCore

struct WorkspaceRootTests {
    private let repo = WorkspaceRoot(workspaceId: "repo", path: "/Users/joao/mocha", isCheckout: true)
    private let worktree = WorkspaceRoot(workspaceId: "w4", path: "/Users/joao/mocha/.claude/worktrees/W4", isCheckout: true)

    private func owner(_ directory: String?, roots: [WorkspaceRoot], excluded: Set<String> = ["/", "/Users/joao"]) -> WorkspaceID? {
        let server = WebServer(pid: 1, process: "node", port: 5173, directory: directory)
        return WorkspaceRoot.assign([server], to: roots, excludedPaths: excluded).first?.workspaceId
    }

    @Test func theLongestContainingRootWins() {
        #expect(owner("/Users/joao/mocha/.claude/worktrees/W4/apps/web", roots: [repo, worktree]) == "w4")
        #expect(owner("/Users/joao/mocha/apps/web", roots: [repo, worktree]) == "repo")
        #expect(owner("/Users/joao/mocha", roots: [repo, worktree]) == "repo")
    }

    @Test func aSiblingWithTheSamePrefixIsNotInside() {
        #expect(owner("/Users/joao/mocha-lab", roots: [repo]) == nil)
    }

    @Test func aCheckoutWinsATieWithAPaneDirectory() {
        let pane = WorkspaceRoot(workspaceId: "repo", path: "/Users/joao/mocha/.claude/worktrees/W4", isCheckout: false)
        #expect(owner("/Users/joao/mocha/.claude/worktrees/W4", roots: [pane, worktree]) == "w4")
        #expect(owner("/Users/joao/mocha/.claude/worktrees/W4", roots: [worktree, pane]) == "w4")
    }

    @Test func homeAndRootNeverOwnServers() {
        let home = WorkspaceRoot(workspaceId: "home", path: "/Users/joao/", isCheckout: false)
        #expect(owner("/Users/joao/Downloads/site", roots: [home]) == nil)
    }

    @Test func aServerWithoutDirectoryHasNoWorkspace() {
        #expect(owner(nil, roots: [repo]) == nil)
    }
}
