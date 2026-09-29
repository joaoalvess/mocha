import Foundation
import MochaTestSupport
import Testing
@testable import MochaHerdr

@Suite(.timeLimit(.minutes(1)))
struct HerdrClientTests {
    @Test func everyRequestUsesItsOwnConnection() async throws {
        try await withFakeHerdr { server, client in
            let pong = try await client.ping()
            let snapshot = try await client.sessionSnapshot()
            let agents = try await client.agentList()
            #expect(pong.protocolVersion == 22)
            #expect(snapshot.panes.map(\.paneId) == ["w1A:p1", "w1A:p2"])
            #expect(agents.map(\.paneId) == ["w1A:p1", "w1A:p2"])
            #expect(await server.connectionCount == 3)
            #expect(await server.requests.map(\.method) == ["ping", "session.snapshot", "agent.list"])
            #expect(Set(await server.requests.map(\.id)).count == 3)
        }
    }

    @Test func concurrentRequestsUseConcurrentConnections() async throws {
        try await withFakeHerdr { server, client in
            async let first = client.agentGet(target: "w1A:p1")
            async let second = client.agentGet(target: "w1A:p2")
            let (one, two) = try await (first, second)
            #expect(one.paneId == "w1A:p1")
            #expect(two.paneId == "w1A:p2")
            #expect(await server.connectionCount == 2)
        }
    }

    @Test func diagnosticMethodsDecode() async throws {
        try await withFakeHerdr { _, client in
            let workspaces = try await client.workspaceList()
            let tabs = try await client.tabList(workspaceId: "w1A")
            let pane = try await client.paneGet(paneId: "w1A:p2")
            #expect(workspaces.map(\.workspaceId) == ["w1A"])
            #expect(tabs.map(\.tabId) == ["w1A:t1"])
            #expect(pane.sessionId == "c31eceaf-ad1d-4b76-b947-380a7f8c668b")
        }
    }

    @Test func paneReadReturnsTheBottomLinesOfTheFakeClaudeScreen() async throws {
        try await withFakeHerdr { server, client in
            let footer = try await client.paneRead(paneId: "w1A:p2", source: .visible, lines: 1)
            #expect(footer.text == "  ⏸ manual mode on · ? for shortcuts · ← for agents")
            #expect(footer.paneId == "w1A:p2")
            #expect(footer.workspaceId == "w1A")
            #expect(footer.truncated)

            await server.setScreen(paneId: "w1A:p2", FakeClaudeScreen(overlay: .effortPicker(cursor: 2)))
            let screen = try await client.paneRead(paneId: "w1A:p2")
            #expect(screen.text.contains("Effort   low  medium  high▲ xhigh  max   Ultracode off"))
            #expect(!screen.truncated)
            _ = await expectServerError(.paneNotFound) { _ = try await client.paneRead(paneId: "w99:p99", lines: 1) }
            #expect(await server.requests(method: "pane.read").first?.intParam("lines") == 1)
        }
    }

    @Test func controlKeysOfTheS8AreAcceptedAndDriveTheFakeScreen() async throws {
        try await withFakeHerdr { server, client in
            try await client.agentSendKeys(target: "w1A:p2", keys: ["shift+tab"])
            try await client.agentSendKeys(target: "w1A:p2", keys: ["Shift+Tab", "SHIFT+TAB"])
            #expect(await server.screen(paneId: "w1A:p2").mode == "auto")
            try await client.agentPrompt(target: "w1A:p2", text: "/model")
            try await client.agentSendKeys(target: "w1A:p2", keys: ["up", "down", "down", "s"])
            #expect(await server.screen(paneId: "w1A:p2").model == "Haiku")
            try await client.agentPrompt(target: "w1A:p2", text: "/effort")
            try await client.agentSendKeys(target: "w1A:p2", keys: ["left", "right", "right", "s"])
            #expect(await server.screen(paneId: "w1A:p2").effort == "xhigh")
            for key in ["S-Tab", "btab", "backtab", "shift-tab"] {
                _ = await expectServerError(.invalidKey) { try await client.agentSendKeys(target: "w1A:p2", keys: [key]) }
            }
        }
    }

    @Test func serverErrorsKeepTheirCodes() async throws {
        try await withFakeHerdr { server, client in
            let notFound = await expectServerError(.agentNotFound) { _ = try await client.agentGet(target: "w99:p99") }
            #expect(notFound?.message == "agent target w99:p99 not found")
            #expect(notFound?.requestId.isEmpty == false)
            await server.setAgentStatus(paneId: "w1A:p1", status: "blocked")
            _ = await expectServerError(.agentBlocked) { _ = try await client.agentPrompt(target: "w1A:p1", text: "oi") }
            _ = await expectServerError(.invalidKey) { try await client.agentSendKeys(target: "w1A:p2", keys: ["Escapee"]) }
            _ = await expectServerError(.paneNotFound) { _ = try await client.paneGet(paneId: "w99:p99") }
            await server.override("agent.get", with: .error(code: "invalid_request", message: "invalid request: missing field `target`"))
            let invalid = await expectServerError(.invalidRequest) { _ = try await client.agentGet(target: "w1A:p1") }
            #expect(invalid?.requestId == "")
            await server.override("agent.get", with: .error(code: "workspace_group_close_required", message: "nope"))
            _ = await expectServerError(.other("workspace_group_close_required")) { _ = try await client.agentGet(target: "w1A:p1") }
        }
    }

    @Test func requestWithoutReplyTimesOut() async throws {
        try await withFakeHerdr(requestTimeout: .milliseconds(150)) { server, client in
            await server.override("ping", with: .noReply)
            let start = ContinuousClock.now
            await #expect(throws: HerdrClientError.timeout(method: "ping")) {
                _ = try await client.ping()
            }
            #expect(start.duration(to: .now) < .seconds(2))
        }
    }

    @Test func promptUsesItsOwnTimeout() async throws {
        try await withFakeHerdr(requestTimeout: .seconds(30), promptTimeout: .milliseconds(150)) { server, client in
            await server.override("agent.prompt", with: .noReply)
            let start = ContinuousClock.now
            await #expect(throws: HerdrClientError.timeout(method: "agent.prompt")) {
                _ = try await client.agentPrompt(target: "w1A:p1", text: "oi")
            }
            #expect(start.duration(to: .now) < .seconds(5))
        }
    }

    @Test func waitCallsUseTheirTimeoutPlusTwoSeconds() {
        let configuration = HerdrClientConfiguration(socketPath: "/tmp/unused.sock")
        #expect(configuration.waitMargin == .seconds(2))
        #expect(configuration.waitTimeout(for: .milliseconds(30000)) == .milliseconds(32000))
        #expect(configuration.waitTimeout(for: .seconds(3)) == .seconds(5))
    }

    @Test func agentWaitIsCutAtItsTimeoutPlusTheMargin() async throws {
        try await withFakeHerdr { server, _ in
            let client = HerdrClient(
                configuration: HerdrClientConfiguration(socketPath: server.socketPath, requestTimeout: .milliseconds(100), waitMargin: .milliseconds(600))
            )
            await server.override("agent.wait", with: .noReply)
            let start = ContinuousClock.now
            await #expect(throws: HerdrClientError.timeout(method: "agent.wait")) {
                _ = try await client.agentWait(target: "w1A:p1", until: [.idle, .blocked], timeout: .milliseconds(400))
            }
            let elapsed = start.duration(to: .now)
            #expect(elapsed >= .milliseconds(990))
            #expect(elapsed < .seconds(5))
            let request = try #require(await server.requests(method: "agent.wait").first)
            #expect(request.intParam("timeout_ms") == 400)
            #expect(request.stringArrayParam("until") == ["idle", "blocked"])
        }
    }

    @Test func agentStartWaitsLongerOnlyWhenItCarriesATimeout() async throws {
        try await withFakeHerdr { server, _ in
            let client = HerdrClient(
                configuration: HerdrClientConfiguration(socketPath: server.socketPath, requestTimeout: .milliseconds(100), waitMargin: .milliseconds(600))
            )
            await server.override("agent.start", with: .noReply)
            let withTimeout = ContinuousClock.now
            await #expect(throws: HerdrClientError.timeout(method: "agent.start")) {
                try await client.agentStart(name: "mocha-1", kind: "claude", paneId: "w1A:p1", args: [], timeout: .milliseconds(400))
            }
            #expect(withTimeout.duration(to: .now) >= .milliseconds(990))
            let withoutTimeout = ContinuousClock.now
            await #expect(throws: HerdrClientError.timeout(method: "agent.start")) {
                try await client.agentStart(name: "mocha-1", kind: "claude", paneId: "w1A:p1", args: [])
            }
            #expect(withoutTimeout.duration(to: .now) < .milliseconds(990))
            let requests = await server.requests(method: "agent.start")
            #expect(requests.map { $0.intParam("timeout_ms") } == [400, nil])
            #expect(requests.map(\.paramKeys) == [["name", "kind", "pane_id", "args", "timeout_ms"], ["name", "kind", "pane_id", "args"]])
        }
    }

    @Test func agentWaitAnswersWhenTheStatusArrives() async throws {
        try await withFakeHerdr { server, client in
            async let waited = client.agentWait(target: "w1A:p1", until: [.idle, .blocked], timeout: .seconds(5))
            #expect(await HerdrWait.until { await server.pendingWaitCount == 1 })
            await server.setAgentStatus(paneId: "w1A:p1", status: "blocked")
            let pane = try await waited
            #expect(pane.paneId == "w1A:p1")
            #expect(pane.agentStatus == .blocked)
            #expect(await server.pendingWaitCount == 0)
        }
    }

    @Test func agentWaitTimeoutComesBackAsTheHerdrError() async throws {
        try await withFakeHerdr { server, client in
            let error = await expectServerError(.timeout) {
                _ = try await client.agentWait(target: "w1A:p1", until: [.working], timeout: .milliseconds(150))
            }
            #expect(error?.message == FakeHerdrServer.waitTimeoutMessage)
            #expect(await server.pendingWaitCount == 0)
        }
    }

    @Test func newTabAndAgentStartDecode() async throws {
        try await withFakeHerdr { server, client in
            let created = try await client.tabCreate(workspaceId: "w1A", cwd: "/Users/dev/projects/demo-app")
            #expect(created.tab.workspaceId == "w1A")
            #expect(created.rootPane.tabId == created.tab.tabId)
            #expect(created.rootPane.cwd == "/Users/dev/projects/demo-app")
            let started = try await client.agentStart(name: "mocha-1", kind: "claude", paneId: created.rootPane.paneId, args: [])
            #expect(started.agent.paneId == created.rootPane.paneId)
            #expect(started.agent.name == "mocha-1")
            #expect(started.argv == ["claude"])
            #expect(try await client.agentList().contains { $0.name == "mocha-1" })
            #expect(await server.requests(method: "tab.create").first?.boolParam("focus") == false)
        }
    }

    @Test func missingSocketFailsToConnect() async throws {
        let client = HerdrClient(configuration: HerdrClientConfiguration(socketPath: FakeHerdrServer.temporarySocketPath(), requestTimeout: .seconds(2)))
        do {
            _ = try await client.ping()
            Issue.record("expected connection failure")
        } catch let error as HerdrClientError {
            #expect(error.isConnectionFailure)
        }
    }

    @Test func closedConnectionWithoutResponseFails() async throws {
        try await withFakeHerdr { server, client in
            await server.override("ping", with: .close)
            await #expect(throws: HerdrClientError.closedWithoutResponse(method: "ping")) {
                _ = try await client.ping()
            }
        }
    }

    @Test func subscriptionDeliversStatusStreamInOrder() async throws {
        try await withFakeHerdr { server, client in
            let subscription = try await client.subscribe([.agentStatusChanged(paneId: "w1A:p1")])
            try await server.play(stream: "stream.status.turn-with-permission.jsonl")
            let events = try await collect(4, from: subscription)
            #expect(
                events.map { event -> HerdrAgentStatus? in
                    if case .agentStatusChanged(_, _, let status, _) = event { status } else { nil }
                } == [.working, .blocked, .working, .done]
            )
            subscription.cancel()
            #expect(await server.writesAfterAck == 0)
        }
    }

    @Test func eventsAreBufferedUntilConsumed() async throws {
        try await withFakeHerdr { server, client in
            let subscription = try await client.subscribe(HerdrSubscription.globalLifecycle)
            try await server.emit(fixture: "event.tab_created.json")
            try await server.emit(fixture: "event.tab_renamed.json")
            try await server.emit(fixture: "event.layout_updated.json")
            try await server.emit(fixture: "event.pane_closed.json")
            let events = try await collect(3, from: subscription)
            #expect(events == [
                .structural("tab_created"),
                .tabRenamed(tabId: "w1A:t1", workspaceId: "w1A", label: "fish"),
                .paneClosed(paneId: "w1A:p2", workspaceId: "w1A"),
            ])
            subscription.cancel()
        }
    }

    @Test func subscriptionEndsWhenTheServerGoesAway() async throws {
        try await withFakeHerdr { server, client in
            let subscription = try await client.subscribe(HerdrSubscription.globalLifecycle)
            await server.stop()
            let ended = try await collect(1, from: subscription, timeout: .seconds(5))
            #expect(ended.isEmpty)
        }
    }

    @Test func subscriptionToUnknownPaneFailsWithProbeId() async throws {
        try await withFakeHerdr { _, client in
            let error = await expectServerError(.paneNotFound) {
                _ = try await client.subscribe([.agentStatusChanged(paneId: "w99:p99")])
            }
            #expect(error?.requestId.hasSuffix(":sub:0:probe") == true)
        }
    }

    @Test func cancelClosesTheSubscriptionConnection() async throws {
        try await withFakeHerdr { server, client in
            let subscription = try await client.subscribe([.agentStatusChanged(paneId: "w1A:p2")])
            #expect(await server.paneSubscriptionIds == ["w1A:p2"])
            subscription.cancel()
            #expect(await HerdrWait.until { await server.paneSubscriptionIds.isEmpty })
            #expect(await server.writesAfterAck == 0)
        }
    }
}
