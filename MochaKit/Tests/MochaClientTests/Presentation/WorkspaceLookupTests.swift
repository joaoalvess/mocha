import MochaProtocol
import Testing
@testable import MochaClient

struct WorkspaceLookupTests {
    @Test func findsAgentsInNestedWorkspaces() {
        let workspaces = PresentationSamples.workspaces
        #expect(workspaces.allAgents.map(\.id) == ["w1:p1", "w1:p2", "w5:p1"])
        #expect(workspaces.agent(withId: "w5:p1")?.title == "Login com a Apple")
        #expect(workspaces.agent(withSessionId: "s-login")?.id == "w5:p1")
        #expect(workspaces.agent(withId: "w9:p9") == nil)
        #expect(workspaces.tab(containingAgent: "w5:p1")?.title == "Claude")
        #expect(workspaces.tab(containingAgent: "w1:p2")?.title == "shell")
    }

    @Test func updatesAgentInNestedWorkspace() {
        var workspaces = PresentationSamples.workspaces
        workspaces.updateAgent(withId: "w5:p1") { $0.status = .blocked }
        #expect(workspaces.agent(withId: "w5:p1")?.status == .blocked)
        #expect(workspaces.agent(withId: "w1:p1")?.status == .idle)
    }
}

enum PresentationSamples {
    static func agent(_ id: AgentID, title: String, sessionId: String?, status: AgentStatus = .idle) -> AgentSummary {
        AgentSummary(id: id, kind: "claude", status: status, title: title, workspaceLabel: "demo", sessionId: sessionId, pendingCount: 0)
    }

    static let workspaces = [
        WorkspaceNode(
            id: "w1",
            label: "demo-app",
            number: 1,
            isDirty: false,
            agentStatus: .idle,
            tabs: [
                TabNode(id: "w1:t1", title: "Claude", agents: [agent("w1:p1", title: "Testes", sessionId: "s-tests")]),
                TabNode(id: "w1:t2", title: "shell", agents: [agent("w1:p2", title: "zsh", sessionId: nil)]),
            ],
            children: [
                WorkspaceNode(
                    id: "w5",
                    label: "login-social",
                    number: 5,
                    isDirty: true,
                    agentStatus: .working,
                    tabs: [TabNode(id: "w5:t1", title: "Claude", agents: [agent("w5:p1", title: "Login com a Apple", sessionId: "s-login", status: .working)])]
                ),
            ]
        ),
    ]
}
