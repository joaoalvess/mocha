import Foundation
import MochaHerdr
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct HerdrBridgeTests {
    @Test func bootstrapSubscribesThenPingsThenSnapshots() async throws {
        let harness = try await HerdrBridgeHarness.make(snapshot: "session.snapshot.response.json")
        let methods = await harness.server.requests.map(\.method)
        #expect(Array(methods.prefix(3)) == ["events.subscribe", "ping", "session.snapshot"])
        let global = try #require(await harness.server.requests.first)
        #expect(global.subscriptions.map(\.type) == HerdrGlobalEventType.allCases.map(\.rawValue))
        #expect(global.subscriptions.allSatisfy { $0.paneId == nil })
        #expect(await harness.bridge.serverInfo == HerdrServerInfo(version: "0.9.1", protocolVersion: 22))
        #expect(await harness.bridge.serverInfo?.protocolWarning == nil)
        #expect(await harness.server.paneSubscriptionIds == ["w17:p1", "wJ:p7"])
        #expect(await HerdrWait.until { await Set(harness.server.requests(method: "agent.get").compactMap { $0.stringParam("target") }) == ["w17:p1", "wJ:p7"] })
        let tree = await harness.bridge.tree()
        #expect(tree.map(\.id) == ["wJ", "w17", "wY", "wW"])
        #expect(treeAgent("w17:p1", in: tree)?.sessionId == "22222222-2222-4222-8222-222222222222")
        #expect(await harness.bridge.agent("w17:p1") == HerdrAgent(
            paneId: "w17:p1",
            workspaceId: "w17",
            kind: "claude",
            status: .idle,
            sessionId: "22222222-2222-4222-8222-222222222222",
            cwd: "/Users/dev/projects/demo-api",
            foregroundCwd: "/Users/dev/projects/demo-api/.claude/worktrees/feature",
            terminalTitle: "revisão do código"
        ))
        #expect(await harness.bridge.agent("wJ:pG") == nil)
        try await harness.finish()
    }

    @Test func everySubscriberStartsWithTheCurrentSnapshot() async throws {
        let harness = try await HerdrBridgeHarness.make(start: false)
        var early = harness.bridge.events().makeAsyncIterator()
        let first = await early.next()
        #expect(first == .snapshot(tree: [], available: false))
        try await harness.start()
        #expect(await harness.waitForTree { !$0.isEmpty })
        let tree = await harness.bridge.tree()
        var second = harness.bridge.events().makeAsyncIterator()
        var third = harness.bridge.events().makeAsyncIterator()
        #expect(await second.next() == .snapshot(tree: tree, available: true))
        #expect(await third.next() == .snapshot(tree: tree, available: true))
        #expect(await early.next() == .treeChanged(tree))
        #expect(await early.next() == .availability(true))
        try await harness.finish()
    }

    @Test func statusStreamUpdatesAgentsAndTree() async throws {
        let harness = try await HerdrBridgeHarness.make()
        try await harness.server.play(stream: "stream.status.turn-with-permission.jsonl")
        #expect(await HerdrWait.until { await herdrStatusEvents(for: "w1A:p1", in: harness.recorder.events).count == 4 })
        #expect(herdrStatusEvents(for: "w1A:p1", in: await harness.recorder.events) == [.working, .blocked, .working, .done])
        try await harness.server.emit(fixture: "event.pane.agent_status_changed.json")
        #expect(await harness.waitForTree { treeWorkspace("w1A", in: $0)?.agentStatus == .working && treeAgent("w1A:p1", in: $0)?.status == .working })
        #expect(await harness.bridge.agent("w1A:p1")?.status == .working)
        let blocked = try HerdrBridgeFixtures.eventLine("event.pane.agent_status_changed.json") { data in
            data["pane_id"] = "w1A:p2"
            data["agent_status"] = "blocked"
        }
        await harness.server.emit(blocked)
        #expect(await harness.waitForTree { treeWorkspace("w1A", in: $0)?.agentStatus == .blocked })
        #expect(await harness.recorder.waitFor { $0 == .agentStatus("w1A:p2", .blocked, title: "Parágrafo sobre chá") } != nil)
        try await harness.finish()
    }

    @Test func linkedWorktreeIsNestedWithBranchAndDirtyFromGit() async throws {
        let git = FakeGitInspector(
            branches: [
                "/Users/dev/projects/demo-app": "main",
                "/Users/dev/projects/demo-app/.claude/worktrees/feature-x": "feature-x",
            ],
            dirtyDirectories: ["/Users/dev/projects/demo-app"]
        )
        let harness = try await HerdrBridgeHarness.make(snapshot: "session.snapshot.linked-worktree.synthetic.json", git: git)
        let tree = await harness.bridge.tree()
        #expect(tree.map(\.id) == ["w5", "w7", "w8"])
        #expect(tree.first?.children.map(\.id) == ["w6"])
        #expect(tree.first?.branch == "main")
        #expect(tree.first?.isDirty == true)
        #expect(tree.first?.children.first?.branch == "feature-x")
        #expect(tree.first?.children.first?.isDirty == false)
        #expect(treeAgent("w5:p3", in: tree)?.branch == "feature-x")
        #expect(Set(git.dirtyChecks) == ["/Users/dev/projects/demo-app", "/Users/dev/projects/demo-app/.claude/worktrees/feature-x"])
        try await harness.finish()
    }

    @Test func reconnectsAfterTheSocketDrops() async throws {
        let harness = try await HerdrBridgeHarness.make()
        let tree = await harness.bridge.tree()
        await harness.server.stop()
        #expect(await harness.recorder.waitFor { $0 == .availability(false) } != nil)
        #expect(await harness.bridge.isAvailable == false)
        #expect(await harness.bridge.tree() == tree)
        await expectHerdrBridgeError(.unavailable) { try await harness.bridge.prompt("w1A:p1", text: "oi") }
        await harness.server.setAgentSession(paneId: "w1A:p2", sessionId: "66666666-6666-4666-8666-666666666666")
        try await harness.server.start()
        #expect(await HerdrWait.until { await harness.bridge.isAvailable })
        #expect(await HerdrWait.until { await harness.recorder.count { $0 == .availability(true) } == 2 })
        #expect(await harness.recorder.waitFor { $0 == .sessionChanged("w1A:p2", sessionId: "66666666-6666-4666-8666-666666666666") } != nil)
        #expect(await HerdrWait.until { await harness.server.paneSubscriptionIds == ["w1A:p1", "w1A:p2"] })
        #expect(await harness.server.globalSubscriptionCount == 1)
        #expect(await harness.requestCount("ping") >= 2)
        try await harness.finish()
    }

    @Test func tabClosedWithoutPaneClosedRemovesPanesAndTheirSubscriptions() async throws {
        let harness = try await HerdrBridgeHarness.make()
        await harness.server.removeTab("w1A:t1")
        try await harness.server.emit(fixture: "event.tab_closed.json")
        #expect(await harness.waitForTree { treeWorkspace("w1A", in: $0)?.tabs.isEmpty == true })
        #expect(await HerdrWait.until { await harness.server.paneSubscriptionIds.isEmpty })
        #expect(await harness.bridge.agent("w1A:p1") == nil)
        #expect(await harness.server.requests.contains { $0.method == "session.snapshot" })
        try await harness.finish()
    }

    @Test func paneExitedWithoutPaneClosedRemovesThePaneAndItsSubscription() async throws {
        let harness = try await HerdrBridgeHarness.make(snapshot: "session.snapshot.linked-worktree.synthetic.json")
        #expect(await harness.server.paneSubscriptionIds.contains("w6:p1"))
        await harness.server.removePanes(["w6:p1"])
        await harness.server.emit(HerdrBridgeFixtures.eventLine(#"{"event":"pane_exited","data":{"type":"pane_exited","pane_id":"w6:p1","workspace_id":"w6"}}"#))
        #expect(await HerdrWait.until { await !harness.server.paneSubscriptionIds.contains("w6:p1") })
        #expect(await harness.waitForTree { treeWorkspace("w6", in: $0)?.tabs.isEmpty == true })
        #expect(await harness.bridge.agent("w6:p1") == nil)
        #expect(await harness.server.paneSubscriptionIds == ["w5:p1", "w5:p3", "w8:p1"])
        try await harness.finish()
    }

    @Test func sessionChangeWithoutEventIsFoundByTheDelayedAgentGet() async throws {
        let harness = try await HerdrBridgeHarness.make()
        let oldSession = "53360f7b-12da-40ad-b37f-37b246ccfc35"
        let newSession = "99999999-9999-4999-8999-999999999999"
        #expect(await HerdrWait.until { await harness.requestCount("agent.get") >= 2 })
        let probesBefore = await harness.requestCount("agent.get")
        await harness.server.setAgentSession(paneId: "w1A:p1", sessionId: newSession)
        let update = try HerdrBridgeFixtures.eventLine("event.pane_updated.json") { data in
            var pane = data["pane"] as? [String: Any] ?? [:]
            var session = pane["agent_session"] as? [String: Any] ?? [:]
            session["value"] = oldSession
            pane["agent_session"] = session
            pane["terminal_title_stripped"] = "Claude Code"
            pane["agent_status"] = "done"
            data["pane"] = pane
        }
        await harness.server.emit(update)
        #expect(await harness.recorder.waitFor { $0 == .sessionChanged("w1A:p1", sessionId: newSession) } != nil)
        #expect(await harness.recorder.count { $0 == .sessionChanged("w1A:p1", sessionId: oldSession) } == 0)
        #expect(await harness.requestCount("agent.get") > probesBefore)
        #expect(await harness.waitForTree { treeAgent("w1A:p1", in: $0)?.sessionId == newSession })
        #expect(await harness.bridge.agent("w1A:p1")?.sessionId == newSession)
        try await harness.finish()
    }

    @Test func sessionInPaneUpdatedIsAppliedDirectly() async throws {
        let harness = try await HerdrBridgeHarness.make()
        await harness.server.setAgentSession(paneId: "w1A:p2", sessionId: "f83af5a9-c009-4ffd-a271-9f12b2409c78")
        await harness.server.setTerminalTitle(paneId: "w1A:p2", title: "Novo título")
        let update = try HerdrBridgeFixtures.eventLine("event.pane_updated.json") { data in
            var pane = data["pane"] as? [String: Any] ?? [:]
            pane["pane_id"] = "w1A:p2"
            pane["terminal_title_stripped"] = "Novo título"
            data["pane"] = pane
        }
        await harness.server.emit(update)
        #expect(await harness.recorder.waitFor { $0 == .sessionChanged("w1A:p2", sessionId: "f83af5a9-c009-4ffd-a271-9f12b2409c78") } != nil)
        #expect(await harness.waitForTree { treeAgent("w1A:p2", in: $0)?.title == "Novo título" })
        try await harness.finish()
    }

    @Test func openChatsDriveTheAgentListReconciliation() async throws {
        let harness = try await HerdrBridgeHarness.make()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await harness.requestCount("agent.list") == 0)
        await harness.bridge.setOpenChats(["w1A:p2"])
        await harness.server.setAgentSession(paneId: "w1A:p2", sessionId: "88888888-8888-4888-8888-888888888888")
        #expect(await harness.recorder.waitFor { $0 == .sessionChanged("w1A:p2", sessionId: "88888888-8888-4888-8888-888888888888") } != nil)
        #expect(await harness.requestCount("agent.list") >= 1)
        await harness.bridge.setOpenChats([])
        try await Task.sleep(for: .milliseconds(100))
        let settled = await harness.requestCount("agent.list")
        try await Task.sleep(for: .milliseconds(250))
        #expect(await harness.requestCount("agent.list") == settled)
        try await harness.finish()
    }

    @Test func workingAgentsAlsoDriveTheReconciliation() async throws {
        let harness = try await HerdrBridgeHarness.make()
        try await harness.server.emit(fixture: "event.pane.agent_status_changed.json")
        #expect(await HerdrWait.until { await harness.requestCount("agent.list") >= 2 })
        try await harness.finish()
    }

    @Test func protocolMismatchWarnsWithoutDroppingTheBridge() async throws {
        let server = FakeHerdrServer()
        try await server.loadSnapshot(fixture: "session.snapshot.two-agents-one-tab.response.json")
        await server.setServerVersion("0.10.0", protocolVersion: 23)
        try await server.start()
        let bridge = HerdrBridge(
            client: HerdrClient(configuration: HerdrClientConfiguration(socketPath: server.socketPath)),
            git: FakeGitInspector(),
            configuration: HerdrBridgeHarness.fastConfiguration
        )
        await bridge.start()
        #expect(await HerdrWait.until { await bridge.isAvailable })
        let info = try #require(await bridge.serverInfo)
        #expect(info.protocolVersion == 23)
        #expect(!info.isSupportedProtocol)
        #expect(info.protocolWarning?.contains("23") == true)
        #expect(await HerdrWait.until { await !bridge.tree().isEmpty })
        await bridge.stop()
        await server.stop()
    }

    @Test func paneMovedIsResolvedAndResubscribedWithTheNewId() async throws {
        let harness = try await HerdrBridgeHarness.make(snapshot: "session.snapshot.linked-worktree.synthetic.json")
        await harness.server.movePane(from: "w5:p3", to: "w6:p2", tabId: "w6:t2", workspaceId: "w6", tabLabel: "claude")
        try await harness.server.emit(fixture: "event.pane_moved.synthetic.json")
        #expect(await harness.recorder.waitFor { $0 == .paneMoved(from: "w5:p3", to: "w6:p2") } != nil)
        #expect(await harness.bridge.resolve("w5:p3") == "w6:p2")
        #expect(await harness.bridge.resolve("w6:p2") == "w6:p2")
        #expect(await harness.bridge.resolve("w9:p9") == "w9:p9")
        #expect(await HerdrWait.until {
            let panes = await harness.server.paneSubscriptionIds
            return panes.contains("w6:p2") && !panes.contains("w5:p3")
        })
        #expect(await harness.waitForTree { tree in
            treeWorkspace("w6", in: tree)?.tabs.contains { $0.id == "w6:t2" && $0.agents.map(\.id) == ["w6:p2"] } == true
                && treeWorkspace("w5", in: tree)?.tabs.map(\.id) == ["w5:t1"]
        })
        await harness.server.movePane(from: "w6:p2", to: "w5:p9", tabId: "w5:t9", workspaceId: "w5", tabLabel: "claude")
        let second = try HerdrBridgeFixtures.eventLine("event.pane_moved.synthetic.json") { data in
            data["previous_pane_id"] = "w6:p2"
            data["previous_workspace_id"] = "w6"
            data["previous_tab_id"] = "w6:t2"
            var pane = data["pane"] as? [String: Any] ?? [:]
            pane["pane_id"] = "w5:p9"
            pane["workspace_id"] = "w5"
            pane["tab_id"] = "w5:t9"
            data["pane"] = pane
        }
        await harness.server.emit(second)
        #expect(await harness.recorder.waitFor { $0 == .paneMoved(from: "w6:p2", to: "w5:p9") } != nil)
        #expect(await harness.bridge.resolve("w5:p3") == "w5:p9")
        #expect(await harness.bridge.resolve("w6:p2") == "w5:p9")
        try await harness.finish()
    }

    @Test func promptAndInterruptSendExplicitTargets() async throws {
        let harness = try await HerdrBridgeHarness.make()
        try await harness.bridge.prompt("w1A:p1", text: "Liste três frutas")
        try await harness.bridge.interrupt("w1A:p2")
        let prompt = try #require(await harness.server.requests(method: "agent.prompt").last)
        #expect(prompt.paramKeys == ["target", "text"])
        #expect(prompt.stringParam("target") == "w1A:p1")
        #expect(prompt.stringParam("text") == "Liste três frutas")
        let keys = try #require(await harness.server.requests(method: "agent.send_keys").last)
        #expect(keys.paramKeys == ["target", "keys"])
        #expect(keys.stringParam("target") == "w1A:p2")
        #expect(keys.stringArrayParam("keys") == ["Escape"])
        try await harness.finish()
    }

    @Test func closeAgentClosesThePaneWhenTheWorkspaceKeepsOtherPanes() async throws {
        let harness = try await HerdrBridgeHarness.make()
        try await harness.bridge.closeAgent("w1A:p2")
        let close = try #require(await harness.server.requests(method: "pane.close").last)
        #expect(close.paramKeys == ["pane_id"])
        #expect(close.stringParam("pane_id") == "w1A:p2")
        #expect(await harness.server.requests(method: "agent.send_keys").isEmpty)
        try await harness.finish()
    }

    @Test func closeAgentQuitsTheAgentWhenItIsTheLastPaneOfTheWorkspace() async throws {
        let harness = try await HerdrBridgeHarness.make(snapshot: "session.snapshot.response.json")
        try await harness.bridge.closeAgent("w17:p1")
        let keys = try #require(await harness.server.requests(method: "agent.send_keys").last)
        #expect(keys.stringParam("target") == "w17:p1")
        #expect(keys.stringArrayParam("keys") == ["C-c", "C-c"])
        #expect(await harness.server.requests(method: "pane.close").isEmpty)
        await expectHerdrBridgeError(.agentNotFound) { try await harness.bridge.closeAgent("w99:p99") }
        try await harness.finish()
    }

    @Test func commandErrorsMapToBridgeErrors() async throws {
        let harness = try await HerdrBridgeHarness.make()
        await harness.server.setAgentStatus(paneId: "w1A:p1", status: "blocked")
        await expectHerdrBridgeError(.agentBlocked) { try await harness.bridge.prompt("w1A:p1", text: "oi") }
        await expectHerdrBridgeError(.agentNotFound) { try await harness.bridge.prompt("w99:p99", text: "oi") }
        await harness.server.override("agent.send_keys", with: .error(code: "pane_not_found", message: "pane w1A:p2 not found"))
        await expectHerdrBridgeError(.agentNotFound) { try await harness.bridge.interrupt("w1A:p2") }
        await harness.server.override("agent.send_keys", with: .error(code: "invalid_key", message: "unsupported key Escape"))
        await expectHerdrBridgeError(.herdr(code: "invalid_key", message: "unsupported key Escape")) { try await harness.bridge.interrupt("w1A:p2") }
        await harness.server.override("agent.prompt", with: .error(code: "agent_prompt_stalled", message: "stalled"))
        await expectHerdrBridgeError(.herdr(code: "agent_prompt_stalled", message: "stalled")) { try await harness.bridge.prompt("w1A:p2", text: "oi") }
        await harness.server.override("agent.prompt", with: .error(code: "timeout", message: "timed out"))
        await expectHerdrBridgeError(.herdr(code: "timeout", message: "timed out")) { try await harness.bridge.prompt("w1A:p2", text: "oi") }
        try await harness.finish()
    }

    @Test func renamesApplyDirectlyWithoutASnapshot() async throws {
        let harness = try await HerdrBridgeHarness.make()
        let snapshots = await harness.requestCount("session.snapshot")
        try await harness.server.emit(HerdrBridgeFixtures.eventLine("event.tab_renamed.json") { $0["label"] = "Claude: revisão" })
        try await harness.server.emit(fixture: "event.workspace_renamed.json")
        #expect(await harness.waitForTree { tree in
            tree.first?.label == "demo-app-tmp" && tree.first?.tabs.first?.title == "Claude: revisão"
                && treeAgent("w1A:p1", in: tree)?.workspaceLabel == "demo-app-tmp"
        })
        #expect(await harness.requestCount("session.snapshot") == snapshots)
        try await harness.finish()
    }

    @Test func detectedAgentGetsItsSubscriptionAndSessionProbes() async throws {
        var configuration = HerdrBridgeHarness.fastConfiguration
        configuration.agentDetectedProbeDelays = [.milliseconds(40), .milliseconds(500)]
        let harness = try await HerdrBridgeHarness.make(
            snapshot: "session.snapshot.linked-worktree.synthetic.json",
            configuration: configuration,
            start: false
        )
        await harness.server.setAgentStatus(paneId: "w6:p1", status: "idle")
        await harness.server.setAgentStatus(paneId: "w8:p1", status: "idle")
        try await harness.start()
        await harness.server.setAgent(paneId: "w7:p1", agent: "claude")
        await harness.server.emit(
            HerdrBridgeFixtures.eventLine(#"{"event":"pane_agent_detected","data":{"type":"pane_agent_detected","pane_id":"w7:p1","workspace_id":"w7","agent":"claude"}}"#)
        )
        #expect(await HerdrWait.until { await harness.server.paneSubscriptionIds.contains("w7:p1") })
        #expect(await HerdrWait.until { await harness.server.requests(method: "agent.get").contains { $0.stringParam("target") == "w7:p1" } })
        #expect(await harness.waitForTree { treeAgent("w7:p1", in: $0)?.kind == "claude" })
        await harness.server.setAgentSession(paneId: "w7:p1", sessionId: "77777777-7777-4777-8777-777777777777")
        #expect(await harness.recorder.waitFor { $0 == .sessionChanged("w7:p1", sessionId: "77777777-7777-4777-8777-777777777777") } != nil)
        #expect(await harness.server.requests(method: "agent.get").filter { $0.stringParam("target") == "w7:p1" }.count >= 2)
        #expect(await harness.requestCount("agent.list") == 0)
        await harness.server.setAgent(paneId: "w7:p1", agent: nil)
        await harness.server.emit(
            HerdrBridgeFixtures.eventLine(
                #"{"event":"pane_agent_detected","data":{"type":"pane_agent_detected","pane_id":"w7:p1","workspace_id":"w7","agent":"claude","released":true,"final_status":"done"}}"#
            )
        )
        #expect(await HerdrWait.until { await !harness.server.paneSubscriptionIds.contains("w7:p1") })
        #expect(await harness.waitForTree { treeWorkspace("w7", in: $0)?.tabs.first?.agents.isEmpty == true })
        try await harness.finish()
    }

    @Test func recordedLifecycleIsDebouncedIntoFewSnapshots() async throws {
        let harness = try await HerdrBridgeHarness.make()
        let before = await harness.requestCount("session.snapshot")
        try await harness.server.play(stream: "stream.global.lab-lifecycle.jsonl")
        #expect(await HerdrWait.until { await harness.requestCount("session.snapshot") > before })
        try await Task.sleep(for: .milliseconds(200))
        let structural = try HerdrFixtures.lines("stream.global.lab-lifecycle.jsonl").compactMap { HerdrEvent(line: $0) }.filter(\.requiresSnapshot).count
        #expect(await harness.requestCount("session.snapshot") - before < structural)
        #expect(await harness.bridge.isAvailable)
        try await harness.finish()
    }

    @Test func stopClosesEveryConnectionAndReportsUnavailable() async throws {
        let harness = try await HerdrBridgeHarness.make()
        await harness.bridge.stop()
        #expect(await harness.recorder.waitFor { $0 == .availability(false) } != nil)
        #expect(await HerdrWait.until { await harness.server.isIdle })
        await expectHerdrBridgeError(.unavailable) { try await harness.bridge.interrupt("w1A:p1") }
        try await harness.finish()
    }
}
