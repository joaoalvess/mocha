import Foundation
import MochaTestSupport
import Testing
@testable import MochaHerdr

@Suite struct HerdrDecodingTests {
    private func decode<Result: Decodable>(_ fixture: String, method: String, type: String, as resultType: Result.Type) throws -> Result {
        try HerdrResponse.decode(HerdrFixtures.data(fixture), method: method, expecting: type, as: resultType)
    }

    @Test func pongCarriesVersionAndProtocol() throws {
        let pong = try decode("ping.response.json", method: "ping", type: "pong", as: HerdrPong.self)
        #expect(pong.version == "0.9.1")
        #expect(pong.protocolVersion == 22)
        #expect(pong.isSupportedProtocol)
    }

    @Test func sessionSnapshotDecodesOmittedOptionalFields() throws {
        let snapshot = try decode(
            "session.snapshot.response.json",
            method: "session.snapshot",
            type: "session_snapshot",
            as: HerdrResponse.Snapshot.self
        ).snapshot
        #expect(snapshot.protocolVersion == 22)
        #expect(snapshot.workspaces.map(\.workspaceId) == ["wJ", "w17", "wY", "wW"])
        #expect(snapshot.workspaces[0].worktree == nil)
        #expect(snapshot.workspaces[1].worktree?.repoName == "demo-api")
        #expect(snapshot.workspaces[1].worktree?.isLinkedWorktree == false)
        #expect(snapshot.tabs.map(\.tabId) == ["wJ:t7", "wJ:tE", "w17:t1", "wY:t2", "wW:t1"])
        let shell = try #require(snapshot.panes.first { $0.paneId == "wJ:pG" })
        #expect(shell.agent == nil)
        #expect(shell.agentSession == nil)
        #expect(shell.agentStatus == .unknown)
        let agent = try #require(snapshot.panes.first { $0.paneId == "w17:p1" })
        #expect(agent.agent == "claude")
        #expect(agent.sessionId == "22222222-2222-4222-8222-222222222222")
        #expect(agent.foregroundCwd == "/Users/dev/projects/demo-api/.claude/worktrees/feature")
        #expect(snapshot.agents.map(\.paneId) == ["wJ:p7", "w17:p1"])
    }

    @Test func twoAgentsShareOneTab() throws {
        let snapshot = try decode(
            "session.snapshot.two-agents-one-tab.response.json",
            method: "session.snapshot",
            type: "session_snapshot",
            as: HerdrResponse.Snapshot.self
        ).snapshot
        #expect(snapshot.panes.map(\.tabId) == ["w1A:t1", "w1A:t1"])
        #expect(Set(snapshot.panes.compactMap(\.sessionId)).count == 2)
    }

    @Test func linkedWorktreeSyntheticSnapshotSharesRepoKey() throws {
        let snapshot = try decode(
            "session.snapshot.linked-worktree.synthetic.json",
            method: "session.snapshot",
            type: "session_snapshot",
            as: HerdrResponse.Snapshot.self
        ).snapshot
        let main = try #require(snapshot.workspaces.first { $0.workspaceId == "w5" }?.worktree)
        let linked = try #require(snapshot.workspaces.first { $0.workspaceId == "w6" }?.worktree)
        #expect(!main.isLinkedWorktree)
        #expect(linked.isLinkedWorktree)
        #expect(main.repoKey == linked.repoKey)
    }

    @Test func agentResponsesDecode() throws {
        let agents = try decode("agent.list.response.json", method: "agent.list", type: "agent_list", as: HerdrResponse.AgentList.self).agents
        #expect(agents.contains { $0.paneId == "w1A:p2" && $0.tabId == "w1A:t1" })
        let info = try decode("agent.get.response.json", method: "agent.get", type: "agent_info", as: HerdrResponse.Agent.self).agent
        #expect(info.agentStatus == .working)
        #expect(info.sessionId == "c31eceaf-ad1d-4b76-b947-380a7f8c668b")
        #expect(info.terminalTitleStripped == "Parágrafo sobre chá")
        let byName = try decode("agent.get.by-name.response.json", method: "agent.get", type: "agent_info", as: HerdrResponse.Agent.self).agent
        #expect(byName.name == "labstart")
        let prompted = try decode("agent.prompt.response.json", method: "agent.prompt", type: "agent_prompted", as: HerdrResponse.Agent.self).agent
        #expect(prompted.agentStatus == .idle)
        _ = try decode("agent.send_keys.response.json", method: "agent.send_keys", type: "ok", as: HerdrResponse.Empty.self)
    }

    @Test func diagnosticResponsesDecode() throws {
        let workspaces = try decode("workspace.list.response.json", method: "workspace.list", type: "workspace_list", as: HerdrResponse.WorkspaceList.self).workspaces
        #expect(workspaces.contains { $0.worktree != nil })
        #expect(workspaces.contains { $0.worktree == nil })
        let tabs = try decode("tab.list.workspace.response.json", method: "tab.list", type: "tab_list", as: HerdrResponse.TabList.self).tabs
        #expect(tabs.first?.label == "Claude: clear")
        let pane = try decode("pane.get.response.json", method: "pane.get", type: "pane_info", as: HerdrResponse.Pane.self).pane
        #expect(pane.agent == "claude")
    }

    @Test(arguments: [
        ("error.agent_blocked.json", HerdrErrorCode.agentBlocked, "r1"),
        ("error.agent_not_found.json", .agentNotFound, "e5"),
        ("error.invalid_key.json", .invalidKey, "r1"),
        ("error.invalid_request.malformed_json.json", .invalidRequest, ""),
        ("error.invalid_request.missing_field.json", .invalidRequest, ""),
        ("error.invalid_request.unknown_method.json", .invalidRequest, ""),
        ("error.pane_not_found.json", .paneNotFound, "e4"),
        ("error.subscription.missing_pane_id.json", .invalidRequest, ""),
        ("error.subscription.pane_not_found.json", .paneNotFound, "x2:sub:0:probe"),
        ("error.timeout.json", .timeout, "r1"),
    ])
    func errorsKeepCodeMessageAndId(fixture: String, code: HerdrErrorCode, requestId: String) throws {
        do {
            _ = try decode(fixture, method: "any", type: "ok", as: HerdrResponse.Empty.self)
            Issue.record("expected error")
        } catch HerdrClientError.server(let error) {
            #expect(error.code == code)
            #expect(error.requestId == requestId)
            #expect(!error.message.isEmpty)
        }
    }

    @Test func unknownErrorCodeBecomesGeneric() throws {
        let line = Data(#"{"id":"r1","error":{"code":"stream_conflict","message":"busy"}}"#.utf8)
        #expect(throws: HerdrClientError.server(HerdrServerError(requestId: "r1", code: .other("stream_conflict"), message: "busy"))) {
            _ = try HerdrResponse.decode(line, method: "agent.get", expecting: "agent_info", as: HerdrResponse.Agent.self)
        }
        #expect(HerdrErrorCode(rawValue: "agent_not_ready") == .agentNotReady)
        #expect(HerdrErrorCode(rawValue: "agent_prompt_stalled") == .agentPromptStalled)
    }

    @Test func unexpectedResultTypeIsInvalidResponse() throws {
        #expect(throws: HerdrClientError.self) {
            _ = try decode("ping.response.json", method: "agent.get", type: "agent_info", as: HerdrResponse.Agent.self)
        }
    }

    @Test func unknownStatusFallsBackToUnknown() throws {
        let line = Data(#"{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","agent_status":"thinking"}"#.utf8)
        let pane = try JSONDecoder().decode(HerdrPane.self, from: line)
        #expect(pane.agentStatus == .unknown)
        #expect(pane.cwd == nil)
    }

    @Test(arguments: [
        ("event.pane_agent_detected.json", HerdrEvent.paneAgentDetected(paneId: "w1A:p1", workspaceId: "w1A", agent: "claude", released: false)),
        ("event.pane_agent_detected.released.json", .paneAgentDetected(paneId: "w1A:p3", workspaceId: "w1A", agent: "claude", released: true)),
        ("event.pane_closed.json", .paneClosed(paneId: "w1A:p2", workspaceId: "w1A")),
        ("event.pane_exited.json", .paneExited(paneId: "w1A:p3", workspaceId: "w1A")),
        ("event.pane.agent_status_changed.json", .agentStatusChanged(paneId: "w1A:p1", workspaceId: "w1A", status: .working, agent: "claude")),
        ("event.pane.agent_status_changed.no-agent.json", .agentStatusChanged(paneId: "w1A:p3", workspaceId: "w1A", status: .unknown, agent: nil)),
        ("event.tab_renamed.json", .tabRenamed(tabId: "w1A:t1", workspaceId: "w1A", label: "fish")),
        ("event.workspace_renamed.json", .workspaceRenamed(workspaceId: "w1A", label: "demo-app-tmp")),
        ("event.tab_closed.json", .structural("tab_closed")),
        ("event.tab_created.json", .structural("tab_created")),
        ("event.tab_moved.json", .structural("tab_moved")),
        ("event.pane_created.json", .structural("pane_created")),
        ("event.workspace_created.json", .structural("workspace_created")),
        ("event.workspace_closed.json", .structural("workspace_closed")),
        ("event.workspace_moved.synthetic.json", .structural("workspace_moved")),
        ("event.workspace_reordered.synthetic.json", .structural("workspace_reordered")),
        ("event.workspace_updated.synthetic.json", .structural("workspace_updated")),
        ("event.worktree_created.synthetic.json", .structural("worktree_created")),
        ("event.worktree_opened.synthetic.json", .structural("worktree_opened")),
        ("event.worktree_removed.synthetic.json", .structural("worktree_removed")),
        ("event.layout_updated.json", .ignored("layout_updated")),
        ("event.workspace_metadata_updated.json", .ignored("workspace_metadata_updated")),
    ])
    func eventsDecodeByWireName(fixture: String, expected: HerdrEvent) throws {
        let event = try #require(HerdrEvent(line: HerdrFixtures.data(fixture)))
        #expect(event == expected)
    }

    @Test func paneEventsCarryThePane() throws {
        let updated = try #require(HerdrEvent(line: HerdrFixtures.data("event.pane_updated.json")))
        guard case .paneUpdated(let pane) = updated else {
            Issue.record("expected pane_updated")
            return
        }
        #expect(pane.sessionId == "f83af5a9-c009-4ffd-a271-9f12b2409c78")
        #expect(pane.terminalTitleStripped == "Claude Code")
        let moved = try #require(HerdrEvent(line: HerdrFixtures.data("event.pane_moved.synthetic.json")))
        guard case .paneMoved(let previous, let movedPane) = moved else {
            Issue.record("expected pane_moved")
            return
        }
        #expect(previous == "w5:p3")
        #expect(movedPane.paneId == "w6:p2")
        #expect(movedPane.tabId == "w6:t2")
    }

    @Test func snapshotIsRequiredOnlyForStructuralEvents() {
        #expect(HerdrEvent.structural("tab_closed").requiresSnapshot)
        #expect(HerdrEvent.paneExited(paneId: "p", workspaceId: "w").requiresSnapshot)
        #expect(HerdrEvent.paneClosed(paneId: "p", workspaceId: "w").requiresSnapshot)
        #expect(HerdrEvent.paneAgentDetected(paneId: "p", workspaceId: "w", agent: nil, released: true).requiresSnapshot)
        #expect(!HerdrEvent.tabRenamed(tabId: "t", workspaceId: "w", label: "x").requiresSnapshot)
        #expect(!HerdrEvent.workspaceRenamed(workspaceId: "w", label: "x").requiresSnapshot)
        #expect(!HerdrEvent.ignored("layout_updated").requiresSnapshot)
    }

    @Test func everyLifecycleLineDecodes() throws {
        let lines = try HerdrFixtures.lines("stream.global.lab-lifecycle.jsonl")
        let events = lines.compactMap { HerdrEvent(line: $0) }
        #expect(events.count == lines.count - 1)
        #expect(events.contains(.paneExited(paneId: "w1A:p3", workspaceId: "w1A")))
        #expect(events.filter { if case .paneUpdated = $0 { true } else { false } }.count == 46)
        #expect(HerdrEvent(line: Data(#"{"id":"sub1","result":{"type":"subscription_started"}}"#.utf8)) == nil)
        #expect(HerdrEvent(line: Data(#"{"event":"pane_zoomed","data":{}}"#.utf8)) == .ignored("pane_zoomed"))
    }
}
