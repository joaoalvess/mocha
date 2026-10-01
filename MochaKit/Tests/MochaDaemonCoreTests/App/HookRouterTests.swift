import CryptoKit
import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct HookRouterTests {
    struct Routing {
        let hooks: HookEventHub
        let router: HookRouter
        let push: PushService
        let transport: FakeApnsTransport
        let clock: ManualClock

        func publish(_ event: HookEvent, agent: AgentID = "w1:p1") {
            hooks.publish(ReceivedHook(agentId: agent, receivedAt: Sample.start, event: event))
        }
    }

    static func withRouting(_ harness: HubHarness, _ body: (Routing) async throws -> Void) async throws {
        let key = try PushTestData.signingKey()
        let transport = FakeApnsTransport()
        let clock = ManualClock(origin: Sample.start)
        let push = PushService(
            devices: harness.devices,
            audience: harness.hub,
            credentials: { ApnsCredentials(config: ApnsConfig(teamId: PushTestData.teamId, keyId: PushTestData.keyId), key: key) },
            transport: transport,
            clock: clock,
            configuration: PushServiceConfiguration(turnDoneCooldown: .zero)
        )
        let hooks = HookEventHub()
        let router = HookRouter(hub: harness.hub, herdr: harness.herdr, push: push)
        await router.start(hooks: hooks.events())
        let routing = Routing(hooks: hooks, router: router, push: push, transport: transport, clock: clock)
        do {
            try await body(routing)
        } catch {
            await router.stop()
            await push.shutdown()
            throw error
        }
        await router.stop()
        await push.shutdown()
    }

    static func sessionStart(_ sessionId: String, path: String, source: SessionStartSource = .clear) -> HookEvent {
        .sessionStart(SessionStartHook(context: HookContext(sessionId: sessionId, transcriptPath: path), source: source))
    }

    @Test func clearSwitchesTheChatToTheHookTranscriptAndArchivesTheOldSessionAsCleared() async throws {
        let path = "/Users/dev/.claude/projects/-Users-dev-projects-demo-app/\(Sample.sessionB).jsonl"
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            try await Self.withRouting(harness) { routing in
                routing.publish(Self.sessionStart(Sample.sessionB, path: path))

                _ = try await eventually { harness.herdr.sessionRefreshCalls.isEmpty ? nil : true }
                #expect(harness.herdr.sessionRefreshCalls == [FakeHerdrSessionRefresh(agentId: "w1:p1", sessionId: Sample.sessionB)])
                let expected = TranscriptSession(sessionId: Sample.sessionB, transcriptPath: path)
                _ = try await eventually { await harness.transcripts.openRequests.contains { $0.session == expected } ? true : nil }
                let ended = try await eventually { harness.archive.endedCalls.first }
                #expect(ended.id == Sample.sessionA)
                #expect(ended.reason == .cleared)
                #expect(await harness.hub.agentSummary("w1:p1")?.sessionId == Sample.sessionB)
                #expect(routing.transport.requests.isEmpty)
            }
        }
    }

    @Test func stopRefreshesTheWorkspaceDirtyStateAndAlertsUnlessTheAgentIsOnScreen() async throws {
        try await withHub { harness in
            let code = await harness.pairing.issueCode(url: Sample.pairingURL)
            let socket = harness.connect()
            let apns = ApnsRegistration(token: PushTestData.deviceToken, env: .sandbox)
            let reply = try await socket.reply(to: .hello(HelloPayload(pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0", apns: apns)), id: "hello-1")
            guard case .helloOk = reply else { throw UnexpectedMessage(message: reply) }
            _ = try await socket.next()
            try await harness.skipSessionState(socket)
            #expect(try await socket.reply(to: .setForeground(agentId: "w1:p1", isActive: true), id: "c-1") == .ack())

            try await Self.withRouting(harness) { routing in
                routing.publish(PushHooks.stop("Feito."))
                _ = try await eventually { harness.herdr.dirtyRefreshCalls.isEmpty ? nil : true }
                #expect(harness.herdr.dirtyRefreshCalls == ["w1:p1"])
                await routing.push.waitForDeliveries()
                #expect(routing.transport.requests.isEmpty)

                #expect(try await socket.reply(to: .setForeground(agentId: "w1:p1", isActive: false), id: "c-2") == .ack())
                routing.publish(PushHooks.stop("Feito de novo."))
                let request = try await eventually { routing.transport.requests.first }
                #expect(request.url?.lastPathComponent == PushTestData.deviceToken)
                let payload = try PushTestData.jsonObject(try #require(request.httpBody))
                let alert = try #require((payload["aps"] as? [String: Any])?["alert"] as? [String: Any])
                #expect(alert["title"] as? String == "Claude terminou · Core")
                #expect(alert["body"] as? String == "Feito de novo.")
                #expect(harness.herdr.dirtyRefreshCalls == ["w1:p1", "w1:p1"])
            }
        }
    }

    @Test func herdrBlockedReachesThePushService() async throws {
        try await withHub { harness in
            _ = try await harness.devices.register(
                name: "iPhone",
                token: "t",
                at: Sample.start,
                apns: ApnsRegistration(token: PushTestData.deviceToken, env: .sandbox)
            )
            try await Self.withRouting(harness) { routing in
                harness.herdr.emit(.agentStatus("w1:p1", .blocked, title: nil))
                try await routing.clock.waitForSleepers(1)
                routing.clock.advance(by: .seconds(1))

                let request = try await eventually { routing.transport.requests.first }
                let payload = try PushTestData.jsonObject(try #require(request.httpBody))
                #expect(payload["kind"] as? String == "needsInput")
                #expect(harness.herdr.sessionRefreshCalls.isEmpty)
            }
        }
    }
}
