import Foundation
import MochaHerdr
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

enum NewAgentTabSupport {
    static func configuration(readyTimeout: Duration) -> HerdrBridgeConfiguration {
        var configuration = HerdrBridgeHarness.fastConfiguration
        configuration.newAgentReadyTimeout = readyTimeout
        return configuration
    }

    static func startedPane(_ server: FakeHerdrServer, count: Int = 1) async throws -> String {
        try #require(await HerdrWait.until { await server.requests(method: "agent.start").count >= count })
        return try #require(await server.requests(method: "agent.start")[count - 1].stringParam("pane_id"))
    }

    static func statusLine(paneId: String, status: String) throws -> Data {
        try HerdrBridgeFixtures.eventLine("event.pane.agent_status_changed.json") { data in
            data["pane_id"] = paneId
            data["agent_status"] = status
        }
    }

    static func trustDialogBlockedLine(paneId: String) throws -> Data {
        let line = try #require(try HerdrFixtures.lines("stream.status.startup-trust-dialog.jsonl").first { line in
            String(decoding: line, as: UTF8.self).contains("\"agent_status\":\"blocked\"")
        })
        return Data(String(decoding: line, as: UTF8.self).replacingOccurrences(of: "w1A:p1", with: paneId).utf8)
    }

    static func agentIsDetected(_ server: FakeHerdrServer, paneId: String, status: String) async {
        await server.setAgent(paneId: paneId, agent: "claude")
        await server.setAgentStatus(paneId: paneId, status: status)
    }

    static func index(_ requests: [FakeHerdrRequest], _ matches: (FakeHerdrRequest) -> Bool) -> Int? {
        requests.firstIndex(where: matches)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HerdrBridgeNewAgentTabTests {
    @Test func createsTheTabStartsClaudeAndAnswersWhenTheAgentIsIdle() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .seconds(20)))
        await harness.server.override("agent.wait", with: .noReply)
        let start = ContinuousClock.now
        async let created = harness.bridge.newAgentTab(in: "w1A")
        let paneId = try await NewAgentTabSupport.startedPane(harness.server)
        #expect(paneId == "w1A:p3")
        try #require(await HerdrWait.until { await harness.requestCount("agent.wait") == 1 })
        await NewAgentTabSupport.agentIsDetected(harness.server, paneId: paneId, status: "idle")
        await harness.server.emit(try NewAgentTabSupport.statusLine(paneId: paneId, status: "idle"))
        #expect(try await created == paneId)
        #expect(start.duration(to: .now) < .seconds(10))

        let requests = await harness.server.requests
        let tabCreate = try #require(NewAgentTabSupport.index(requests) { $0.method == "tab.create" })
        let subscription = try #require(NewAgentTabSupport.index(requests) { $0.method == "events.subscribe" && $0.subscriptions.contains { $0.paneId == paneId } })
        let agentList = try #require(requests.indices.first { $0 > tabCreate && requests[$0].method == "agent.list" })
        let agentStart = try #require(NewAgentTabSupport.index(requests) { $0.method == "agent.start" })
        let agentWait = try #require(NewAgentTabSupport.index(requests) { $0.method == "agent.wait" })
        #expect(tabCreate < subscription)
        #expect(subscription < agentStart)
        #expect(agentList < agentStart)
        #expect(agentStart < agentWait)

        #expect(requests[tabCreate].paramKeys == ["workspace_id", "cwd", "focus"])
        #expect(requests[tabCreate].stringParam("workspace_id") == "w1A")
        #expect(requests[tabCreate].stringParam("cwd") == "/Users/dev/projects/demo-app")
        #expect(requests[tabCreate].boolParam("focus") == false)
        #expect(requests[subscription].subscriptions.map(\.type) == ["pane.agent_status_changed"])
        #expect(requests[agentStart].paramKeys == ["name", "kind", "pane_id", "args"])
        #expect(requests[agentStart].stringParam("name") == "mocha-1")
        #expect(requests[agentStart].stringParam("kind") == "claude")
        #expect(requests[agentStart].stringParam("pane_id") == paneId)
        #expect(requests[agentStart].stringArrayParam("args") == [])
        #expect(requests[agentWait].stringParam("target") == paneId)
        #expect(requests[agentWait].stringArrayParam("until") == ["idle", "blocked"])
        #expect(requests[agentWait].intParam("timeout_ms") == 20000)

        #expect(await harness.bridge.agent(paneId) == HerdrAgent(
            paneId: paneId,
            workspaceId: "w1A",
            kind: "claude",
            status: .idle,
            cwd: "/Users/dev/projects/demo-app",
            foregroundCwd: "/Users/dev/projects/demo-app"
        ))
        #expect(await harness.waitForTree { treeAgent(paneId, in: $0)?.status == .idle })
        #expect(await harness.requestCount("agent.send_keys") == 0)
        #expect(await harness.requestCount("agent.prompt") == 0)
        try await harness.finish()
    }

    @Test func trustDialogBlockedAnswersTheSameWayWithoutTouchingTheDialog() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .seconds(20)))
        await harness.server.override("agent.wait", with: .noReply)
        let start = ContinuousClock.now
        async let created = harness.bridge.newAgentTab(in: "w1A")
        let paneId = try await NewAgentTabSupport.startedPane(harness.server)
        await NewAgentTabSupport.agentIsDetected(harness.server, paneId: paneId, status: "blocked")
        await harness.server.emit(try NewAgentTabSupport.trustDialogBlockedLine(paneId: paneId))
        #expect(try await created == paneId)
        #expect(start.duration(to: .now) < .seconds(10))
        #expect(await harness.bridge.agent(paneId)?.status == .blocked)
        #expect(await harness.waitForTree { treeWorkspace("w1A", in: $0)?.agentStatus == .blocked })
        #expect(await harness.requestCount("agent.send_keys") == 0)
        #expect(await harness.requestCount("agent.prompt") == 0)
        try await harness.finish()
    }

    @Test func agentWaitAloneAlsoEndsTheWait() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .seconds(20)))
        let start = ContinuousClock.now
        async let created = harness.bridge.newAgentTab(in: "w1A")
        let paneId = try await NewAgentTabSupport.startedPane(harness.server)
        #expect(await HerdrWait.until { await harness.server.pendingWaitCount == 1 })
        await NewAgentTabSupport.agentIsDetected(harness.server, paneId: paneId, status: "idle")
        #expect(try await created == paneId)
        #expect(start.duration(to: .now) < .seconds(10))
        #expect(await harness.bridge.agent(paneId)?.kind == "claude")
        try await harness.finish()
    }

    @Test func answersAfterTheReadyTimeoutWithoutIdleOrBlocked() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(300)))
        let start = ContinuousClock.now
        let paneId = try await harness.bridge.newAgentTab(in: "w1A")
        let elapsed = start.duration(to: .now)
        #expect(paneId == "w1A:p3")
        #expect(elapsed >= .milliseconds(290))
        #expect(elapsed < .seconds(5))
        #expect(await harness.server.requests(method: "agent.wait").first?.intParam("timeout_ms") == 300)
        try await harness.finish()
    }

    @Test func namesTheAgentWithTheSmallestFreeNumber() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(50)))
        var panes: [AgentID] = []
        for _ in 0..<3 {
            panes.append(try await harness.bridge.newAgentTab(in: "w1A"))
        }
        await harness.server.removePanes([panes[1]])
        _ = try await harness.bridge.newAgentTab(in: "w1A")
        let names = await harness.server.requests(method: "agent.start").compactMap { $0.stringParam("name") }
        #expect(names == ["mocha-1", "mocha-2", "mocha-3", "mocha-2"])
        #expect(HerdrBridge.newAgentName(excluding: ["mocha-1", "mocha-3", "labstart"]) == "mocha-2")
        #expect(HerdrBridge.newAgentName(excluding: []) == "mocha-1")
        try await harness.finish()
    }

    @Test func concurrentTabsNeverShareAName() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(100)))
        async let first = harness.bridge.newAgentTab(in: "w1A")
        async let second = harness.bridge.newAgentTab(in: "w1A")
        let panes = try await [first, second]
        #expect(Set(panes).count == 2)
        let names = await harness.server.requests(method: "agent.start").compactMap { $0.stringParam("name") }
        #expect(Set(names) == ["mocha-1", "mocha-2"])
        try await harness.finish()
    }

    @Test func cwdIsTheWorkspaceDirectory() async throws {
        let harness = try await HerdrBridgeHarness.make(
            snapshot: "session.snapshot.linked-worktree.synthetic.json",
            configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(50))
        )
        _ = try await harness.bridge.newAgentTab(in: "w6")
        _ = try await harness.bridge.newAgentTab(in: "w7")
        let requests = await harness.server.requests(method: "tab.create")
        #expect(requests.map { $0.stringParam("workspace_id") } == ["w6", "w7"])
        #expect(requests.map { $0.stringParam("cwd") } == ["/Users/dev/projects/demo-app/.claude/worktrees/feature-x", "/Users/dev/projects/notes"])
        try await harness.finish()
    }

    @Test func unknownWorkspaceAndMissingHerdrAreRejectedBeforeAnyRequest() async throws {
        let harness = try await HerdrBridgeHarness.make(start: false)
        await expectHerdrBridgeError(.unavailable) { _ = try await harness.bridge.newAgentTab(in: "w1A") }
        try await harness.start()
        await expectHerdrBridgeError(.workspaceNotFound) { _ = try await harness.bridge.newAgentTab(in: "w99") }
        #expect(await harness.requestCount("tab.create") == 0)
        try await harness.finish()
    }

    @Test func tabCreateErrorsStopBeforeStartingTheAgent() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(50)))
        await harness.server.override("tab.create", with: .error(code: "not_found", message: "workspace w1A not found"))
        await expectHerdrBridgeError(.herdr(code: "not_found", message: "workspace w1A not found")) {
            _ = try await harness.bridge.newAgentTab(in: "w1A")
        }
        await harness.server.override("tab.create", with: .error(code: "pane_not_found", message: "pane w1A:p9 not found"))
        await expectHerdrBridgeError(.agentNotFound) { _ = try await harness.bridge.newAgentTab(in: "w1A") }
        #expect(await harness.requestCount("agent.start") == 0)
        try await harness.finish()
    }

    @Test func agentStartFailureLeavesTheTabOpenAndFreesTheName() async throws {
        let harness = try await HerdrBridgeHarness.make(configuration: NewAgentTabSupport.configuration(readyTimeout: .milliseconds(50)))
        await harness.server.override("agent.start", with: .error(code: "agent_not_ready", message: "pane is not at a shell prompt"))
        await expectHerdrBridgeError(.herdr(code: "agent_not_ready", message: "pane is not at a shell prompt")) {
            _ = try await harness.bridge.newAgentTab(in: "w1A")
        }
        let snapshot = try await harness.client().sessionSnapshot()
        #expect(snapshot.tabs.map(\.tabId) == ["w1A:t1", "w1A:t2"])
        #expect(snapshot.panes.contains { $0.paneId == "w1A:p3" })
        #expect(await harness.requestCount("agent.wait") == 0)
        await harness.server.override("agent.start", with: nil)
        _ = try await harness.bridge.newAgentTab(in: "w1A")
        let names = await harness.server.requests(method: "agent.start").compactMap { $0.stringParam("name") }
        #expect(names == ["mocha-1", "mocha-1"])
        try await harness.finish()
    }
}
