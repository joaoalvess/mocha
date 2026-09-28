import MochaProtocol
import Testing
@testable import MochaClient

struct WebServerGroupingTests {
    private let workspaces = PresentationSamples.workspaces
    private let servers = [
        WebServer(pid: 3, process: "ssh", port: 8181),
        WebServer(pid: 2, process: "node", port: 5174, workspaceId: "w5"),
        WebServer(pid: 1, process: "node", port: 5173, workspaceId: "w1"),
        WebServer(pid: 4, process: "node", port: 3000, workspaceId: "w1"),
        WebServer(pid: 5, process: "node", port: 4000, workspaceId: "w9"),
    ]

    @Test func groupsFollowTheWorkspaceTreeAndUnassignedGoLastUnderTheHost() {
        let groups = WebServerGrouping.groups(servers: servers, host: "MacBook", workspaces: workspaces)
        #expect(groups.map(\.title) == ["demo-app", "login-social", "MacBook"])
        #expect(groups.map { $0.servers.map(\.port) } == [[3000, 5173], [5174], [4000, 8181]])
    }

    @Test func aScopeKeepsOnlyThatWorkspace() {
        let groups = WebServerGrouping.groups(servers: servers, host: "MacBook", workspaces: workspaces, scope: "w5")
        #expect(groups == [WebServerGroup(id: "w5", title: "login-social", servers: [servers[1]])])
    }

    @Test func aScopeWithoutServersKeepsAnEmptyGroup() {
        let groups = WebServerGrouping.groups(servers: [servers[0]], host: "MacBook", workspaces: workspaces, scope: "w1")
        #expect(groups == [WebServerGroup(id: "w1", title: "demo-app", servers: [])])
    }

    @Test func findsTheInnermostWorkspaceOfAnAgent() {
        #expect(workspaces.workspaceNode(containingAgent: "w5:p1")?.id == "w5")
        #expect(workspaces.workspaceNode(containingAgent: "w1:p2")?.id == "w1")
        #expect(workspaces.workspaceNode(containingAgent: "w9:p9") == nil)
    }
}
