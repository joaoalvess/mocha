import MochaProtocol
import Testing
@testable import MochaDemo

private func workspace(_ statuses: [AgentStatus]) -> WorkspaceNode {
    WorkspaceNode(
        id: "w1",
        label: "demo-app",
        number: 1,
        isDirty: false,
        agentStatus: .unknown,
        tabs: statuses.enumerated().map { index, status in
            TabNode(
                id: "w1:t\(index)",
                title: "Claude",
                agents: [AgentSummary(id: "w1:p\(index)", kind: "claude", status: status, title: "t", workspaceLabel: "demo-app")]
            )
        } + [TabNode(id: "w1:shell", title: "zsh")],
        children: [
            WorkspaceNode(
                id: "w2",
                label: "filho",
                number: 2,
                isDirty: false,
                agentStatus: .blocked,
                tabs: [TabNode(id: "w2:t1", title: "Claude", agents: [AgentSummary(id: "w2:p1", kind: "claude", status: .blocked, title: "t", workspaceLabel: "filho")])]
            ),
        ]
    )
}

@Suite struct DemoTreeTests {
    @Test(arguments: [
        ([], AgentStatus.unknown),
        ([.unknown], .unknown),
        ([.unknown, .idle], .idle),
        ([.idle, .done], .done),
        ([.done, .working, .idle], .working),
        ([.working, .blocked, .done], .blocked),
    ] as [([AgentStatus], AgentStatus)])
    func aggregatePrefersBlockedThenWorkingThenDoneThenIdleThenUnknown(statuses: [AgentStatus], expected: AgentStatus) {
        #expect(workspace(statuses).aggregatedAgentStatus == expected)
    }

    @Test func updatingAnAgentRecomputesOnlyItsWorkspace() throws {
        var workspaces = [workspace([.idle, .idle])]

        let updated = workspaces.updateAgent(withId: "w1:p1") { $0.status = .working }

        #expect(updated)
        #expect(workspaces[0].agentStatus == .working)
        #expect(workspaces[0].children[0].agentStatus == .blocked)
        #expect(workspaces.agent(withId: "w1:p1")?.status == .working)
        #expect(workspaces.updateAgent(withId: "w9:p9") { $0.status = .done } == false)

        workspaces.updateAgent(withId: "w2:p1") { $0.status = .idle }
        #expect(workspaces[0].children[0].agentStatus == .idle)
        #expect(workspaces[0].agentStatus == .working)
    }
}
