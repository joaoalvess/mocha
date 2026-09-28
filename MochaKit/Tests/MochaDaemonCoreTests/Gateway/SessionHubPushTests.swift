import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubPushTests {
    static let sandbox = ApnsRegistration(token: String(repeating: "ab", count: 32), env: .sandbox)
    static let production = ApnsRegistration(token: String(repeating: "cd", count: 32), env: .production)

    static func hello(_ harness: HubHarness, _ payload: HelloPayload) async throws -> (socket: TestClientSocket, helloOk: HelloOkPayload) {
        let socket = harness.connect()
        let reply = try await socket.reply(to: .hello(payload), id: "hello-1")
        guard case .helloOk(let helloOk) = reply else { throw UnexpectedMessage(message: reply) }
        _ = try await socket.next()
        try await harness.skipSessionState(socket)
        return (socket, helloOk)
    }

    static func pair(_ harness: HubHarness, apns: ApnsRegistration?) async throws -> (socket: TestClientSocket, helloOk: HelloOkPayload) {
        let code = await harness.pairing.issueCode(url: Sample.pairingURL)
        return try await hello(harness, HelloPayload(pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0", apns: apns))
    }

    static func reconnect(_ harness: HubHarness, token: String, apns: ApnsRegistration?) async throws -> HelloOkPayload {
        try await hello(harness, HelloPayload(deviceToken: token, deviceName: "iPhone", appVersion: "1.0", apns: apns)).helloOk
    }

    @Test func slashIsSentToTheAgentAsAPrompt() async throws {
        try await withHub(tree: Sample.unsupportedTree) { harness in
            let (socket, _) = try await harness.pairedClient()

            #expect(try await socket.reply(to: .slash(agentId: "w1:p1", command: "/compact"), id: "c-1") == .ack())
            #expect(try await socket.reply(to: .slash(agentId: "w1:p2", command: "/clear"), id: "c-2").errorCode == .invalidPayload)
            #expect(try await socket.reply(to: .slash(agentId: "w9:p9", command: "/clear"), id: "c-3").errorCode == .agentNotFound)

            #expect(harness.herdr.promptCalls == [FakeHerdrPromptCall(agentId: "w1:p1", text: "/compact")])
        }
    }

    @Test func slashFollowsAMovedPaneAndReportsHerdrErrors() async throws {
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            harness.herdr.movePane(from: "w1:p1", to: "w1:p7")
            _ = try await eventually { await harness.hub.agentSummary("w1:p7") }

            #expect(try await socket.reply(to: .slash(agentId: "w1:p1", command: "/cost"), id: "c-1") == .ack())
            harness.herdr.setPromptError(.agentBlocked)
            #expect(try await socket.reply(to: .slash(agentId: "w1:p7", command: "/cost"), id: "c-2").errorCode == .agentBlocked)

            #expect(harness.herdr.promptCalls.map(\.agentId) == ["w1:p7", "w1:p7"])
        }
    }

    @Test func preferencesAreSavedAndComeBackInTheNextHello() async throws {
        try await withHub { harness in
            let (socket, helloOk) = try await harness.pairedClient()
            #expect(helloOk.preferences == DevicePreferences(turnDoneAlerts: true))

            #expect(try await socket.reply(to: .setPreferences(DevicePreferences(turnDoneAlerts: false))) == .ack())

            #expect(try await harness.devices.devices().first?.preferences == DevicePreferences(turnDoneAlerts: false))
            let token = try #require(helloOk.deviceToken)
            #expect(try await Self.reconnect(harness, token: token, apns: nil).preferences == DevicePreferences(turnDoneAlerts: false))
        }
    }

    @Test func helloApnsIsStoredKeptWhenAbsentAndReplaced() async throws {
        try await withHub { harness in
            let (_, helloOk) = try await Self.pair(harness, apns: Self.sandbox)
            let token = try #require(helloOk.deviceToken)
            #expect(try await harness.devices.devices().first?.apns == Self.sandbox)

            _ = try await Self.reconnect(harness, token: token, apns: nil)
            #expect(try await harness.devices.devices().first?.apns == Self.sandbox)

            _ = try await Self.reconnect(harness, token: token, apns: Self.production)
            #expect(try await harness.devices.devices().first?.apns == Self.production)

            _ = try await Self.reconnect(harness, token: token, apns: ApnsRegistration(token: "nao-e-hex", env: .sandbox))
            #expect(try await harness.devices.devices().first?.apns == Self.production)

            let text = try String(contentsOf: harness.devices.fileURL, encoding: .utf8)
            #expect(text.contains(#""env" : "production""#))
            #expect(text.contains(Self.production.token))
        }
    }

    @Test func aTokenMovesToTheDeviceThatSentItLast() async throws {
        try await withHub { harness in
            let (_, first) = try await Self.pair(harness, apns: Self.sandbox)
            let (_, second) = try await Self.pair(harness, apns: ApnsRegistration(token: Self.sandbox.token.uppercased(), env: .sandbox))

            let records = try await harness.devices.devices()
            #expect(records.first { $0.id == first.deviceId }?.apns == nil)
            #expect(records.first { $0.id == second.deviceId }?.apns == Self.sandbox)
        }
    }

    @Test func foregroundDevicesFollowSetForeground() async throws {
        try await withHub { harness in
            let (socket, helloOk) = try await harness.pairedClient()
            #expect(await harness.hub.foregroundDevices(for: "w1:p1").isEmpty)

            #expect(try await socket.reply(to: .setForeground(agentId: "w1:p1", isActive: true)) == .ack())
            #expect(await harness.hub.foregroundDevices(for: "w1:p1") == [helloOk.deviceId])
            #expect(await harness.hub.foregroundDevices(for: "w1:p2").isEmpty)

            harness.herdr.movePane(from: "w1:p1", to: "w1:p8")
            _ = try await eventually { await harness.hub.foregroundDevices(for: "w1:p8") == [helloOk.deviceId] ? true : nil }

            #expect(try await socket.reply(to: .setForeground(agentId: "w1:p8", isActive: false), id: "c-2") == .ack())
            #expect(await harness.hub.foregroundDevices(for: "w1:p8").isEmpty)

            #expect(try await socket.reply(to: .setForeground(agentId: "w1:p8", isActive: true), id: "c-3") == .ack())
            socket.disconnect()
            _ = try await eventually { await harness.hub.foregroundDevices(for: "w1:p8").isEmpty ? true : nil }
        }
    }

    @Test func agentSummaryCarriesTheWorkspaceLabel() async throws {
        try await withHub { harness in
            #expect(await harness.hub.agentSummary("w1:p1")?.workspaceLabel == "Core")
            #expect(await harness.hub.agentSummary("w1:p1")?.kind == "claude")
            #expect(await harness.hub.agentSummary("w9:p9") == nil)
        }
    }

    @Test func theHookTranscriptPathIsUsedToFollowTheSession() async throws {
        let path = "/Users/dev/.claude/projects/-Users-dev-projects-demo-app/\(Sample.sessionB).jsonl"
        try await withHub { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
            await harness.hub.hookReceived(ReceivedHook(
                agentId: "w1:p1",
                receivedAt: Sample.start,
                event: .sessionStart(SessionStartHook(context: HookContext(sessionId: Sample.sessionB, transcriptPath: path), source: .clear))
            ))

            harness.herdr.setAgent(HerdrAgent(paneId: "w1:p1", workspaceId: "w1", kind: "claude", status: .idle, sessionId: Sample.sessionB))
            harness.herdr.emit(.sessionChanged("w1:p1", sessionId: Sample.sessionB))

            let expected = TranscriptSession(sessionId: Sample.sessionB, transcriptPath: path)
            _ = try await eventually { await harness.transcripts.openRequests.contains { $0.session == expected } ? true : nil }
            #expect(await harness.transcripts.openRequests.contains { $0.session == TranscriptSession(sessionId: Sample.sessionA) })
        }
    }
}
