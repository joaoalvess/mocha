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
