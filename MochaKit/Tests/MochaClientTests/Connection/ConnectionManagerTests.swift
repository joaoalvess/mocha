import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaClient

@Suite(.timeLimit(.minutes(1)))
struct ConnectionManagerTests {
    struct Harness {
        let clock = ManualClock()
        let transport: FakeTransport
        let store: FakeTokenStore
        let path = FakePathMonitor()
        let manager: ConnectionManager
        let states: Recorder<ConnectionState>
        let messages: Recorder<ServerEnvelope>

        init(
            credential: DeviceCredential? = nil,
            apnsRegistration: any ApnsRegistrationSource = NoApnsRegistration(),
            answersPings: Bool = true,
            jitter: @escaping @Sendable () -> Double = { 1 }
        ) {
            transport = FakeTransport(clock: clock, answersPings: answersPings)
            store = FakeTokenStore(credential: credential)
            manager = ConnectionManager(
                configuration: ConnectionFixtures.configuration,
                tokenStore: store,
                apnsRegistration: apnsRegistration,
                transport: transport,
                clock: clock,
                pathMonitor: path,
                jitter: jitter
            )
            states = Recorder(manager.states)
            messages = Recorder(manager.messages)
        }

        func connect(channel index: Int = 0, token: String? = nil) async throws -> FakeChannel {
            let channel = try await transport.channel(index)
            try await waitUntil { channel.hello != nil }
            try channel.deliver(ConnectionFixtures.helloOk(token: token), id: channel.sentEnvelopes.first?.id)
            try channel.deliver(.tree(workspaces: []), id: channel.sentEnvelopes.first?.id)
            try await states.wait(for: .connected)
            return channel
        }

        func pendingRetryDelay() async throws -> Duration {
            try await waitUntil { clock.pendingSleeps.contains { $0 != ConnectionConfiguration.pingInterval } }
            return try #require(clock.pendingSleeps.first { $0 != ConnectionConfiguration.pingInterval })
        }
    }

    @Test func statesStartWithIdle() async throws {
        let harness = Harness()
        try await waitUntil { harness.states.all.first == .idle }
    }

    @Test func startWithoutCredentialRequiresPairing() async throws {
        let harness = Harness()
        await harness.manager.start()
        try await harness.states.wait(for: .pairingRequired(nil))
        #expect(harness.transport.channelCount == 0)
    }

    @Test func startWithCredentialSendsHelloWithToken() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        #expect(channel.url == ConnectionFixtures.url)
        #expect(channel.sentEnvelopes.first?.id == "hello-1")
        #expect(channel.hello?.deviceToken == "stored-token")
        #expect(channel.hello?.pairingCode == nil)
        #expect(channel.hello?.deviceName == "iPhone")
        #expect(channel.hello?.appVersion == "0.1.0")
        #expect(harness.states.last == .connecting)
    }

    @Test func helloWithoutApnsTokenOmitsTheRegistration() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        #expect(channel.hello?.apns == nil)
    }

    @Test func helloCarriesTheApnsTokenAndEnvironment() async throws {
        let registration = ApnsRegistration(token: "a1b2c3d4", env: .sandbox)
        let harness = Harness(credential: ConnectionFixtures.credential, apnsRegistration: ApnsRegistrationBox(registration))
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        #expect(channel.hello?.apns == registration)
    }

    @Test func pairingHelloCarriesTheApnsToken() async throws {
        let registration = ApnsRegistration(token: "a1b2c3d4", env: .production)
        let harness = Harness(apnsRegistration: ApnsRegistrationBox(registration))
        await harness.manager.pair(ConnectionFixtures.link)
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        #expect(channel.hello?.pairingCode == ConnectionFixtures.link.code)
        #expect(channel.hello?.apns == registration)
    }

    @Test func tokenThatArrivesLaterGoesInTheNextHello() async throws {
        let box = ApnsRegistrationBox()
        let harness = Harness(credential: ConnectionFixtures.credential, apnsRegistration: box)
        await harness.manager.start()
        let first = try await harness.connect()
        #expect(first.hello?.apns == nil)
        let registration = ApnsRegistration(token: "0f0e0d0c", env: .sandbox)
        box.update(registration)
        await harness.manager.stop()
        await harness.manager.start()
        let second = try await harness.connect(channel: 1)
        #expect(second.hello?.apns == registration)
    }

    @Test func startIsIdempotent() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        await harness.manager.start()
        _ = try await harness.connect()
        await harness.manager.start()
        #expect(harness.transport.channelCount == 1)
    }

    @Test func pairingByCodeSavesTheTokenAndConnects() async throws {
        let harness = Harness()
        await harness.manager.pair(ConnectionFixtures.link)
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        #expect(channel.hello?.pairingCode == "abc-DEF_123")
        #expect(channel.hello?.deviceToken == nil)
        _ = try await harness.connect(token: "new-token")
        #expect(await harness.store.credential == DeviceCredential(url: ConnectionFixtures.url, token: "new-token"))
        try await waitUntil { harness.messages.all.count == 2 }
        #expect(harness.messages.all.map(\.message.type) == ["helloOk", "tree"])
        #expect(harness.messages.all.allSatisfy { $0.id == "hello-1" })
    }

    @Test func reconnectionAfterPairingUsesTheNewToken() async throws {
        let harness = Harness()
        await harness.manager.pair(ConnectionFixtures.link)
        let first = try await harness.connect(token: "new-token")
        first.fail(.network)
        try await harness.states.wait(for: .waitingToRetry(.unreachable))
        harness.clock.advance(by: try await harness.pendingRetryDelay())
        let second = try await harness.transport.channel(1)
        try await waitUntil { second.hello != nil }
        #expect(second.hello?.deviceToken == "new-token")
        #expect(second.hello?.pairingCode == nil)
        #expect(second.sentEnvelopes.first?.id == "hello-2")
    }

    @Test func unauthorizedHelloRequiresPairingWithoutDeletingTheToken() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        try channel.deliver(.error(code: .unauthorized, message: "Aparelho não autorizado."), id: "hello-1")
        try await harness.states.wait(for: .pairingRequired(.unauthorized))
        #expect(await harness.store.credential == ConnectionFixtures.credential)
        #expect(await harness.store.deleteCount == 0)
        #expect(channel.closeCode == .normalClosure)
    }

    @Test func expiredPairingCodeRequiresPairingWithoutTouchingTheToken() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.pair(ConnectionFixtures.link)
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        try channel.deliver(.error(code: .pairingExpired, message: "Código vencido."), id: "hello-1")
        try await harness.states.wait(for: .pairingRequired(.pairingExpired))
        #expect(await harness.store.credential == ConnectionFixtures.credential)
        #expect(await harness.store.saveCount == 0)
        #expect(await harness.store.deleteCount == 0)
    }

    @Test func removedDeviceRequiresPairingWithoutDeletingTheToken() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.connect()
        try channel.deliver(.error(code: .unauthorized, message: "Este aparelho foi removido do Mac."))
        try await harness.states.wait(for: .pairingRequired(.unauthorized))
        #expect(await harness.store.credential == ConnectionFixtures.credential)
    }

    @Test func policyViolationCloseRequiresPairing() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.connect()
        channel.fail(.closed(code: 1008))
        try await harness.states.wait(for: .pairingRequired(.unauthorized))
        #expect(await harness.store.credential == ConnectionFixtures.credential)
    }

    @Test func protocolMismatchFailsUntilTheNextStart() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        try channel.deliver(.error(code: .protocolMismatch, message: "Versão de protocolo não suportada."), id: "hello-1")
        try await harness.states.wait(for: .failed(.protocolMismatch))
        #expect(harness.clock.sleeperCount == 0)
        await harness.manager.start()
        _ = try await harness.transport.channel(1)
    }

    @Test func unpairDeletesTheTokenAfterTheAck() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.connect()
        try await harness.manager.send(.unpair, id: "c-1")
        #expect(channel.sentEnvelopes.last == ClientEnvelope(id: "c-1", message: .unpair))
        #expect(await harness.store.credential == ConnectionFixtures.credential)
        try channel.deliver(.ack(), id: "c-1")
        try await harness.states.wait(for: .pairingRequired(nil))
        #expect(await harness.store.credential == nil)
        #expect(await harness.store.deleteCount == 1)
        #expect(harness.messages.all.last == ServerEnvelope(id: "c-1", message: .ack()))
        await harness.manager.stop()
        await harness.manager.start()
        try await harness.states.wait(for: .pairingRequired(nil))
        #expect(harness.transport.channelCount == 1)
    }

    @Test func sendOutsideConnectedThrowsNotConnected() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.manager.send(.ping, id: "c-1")
        }
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        try await waitUntil { channel.hello != nil }
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.manager.send(.ping, id: "c-2")
        }
        _ = try await harness.connect()
        try await harness.manager.send(.ping, id: "c-3")
        #expect(channel.sentEnvelopes.last?.id == "c-3")
    }

    @Test func badGatewayMeansTheDaemonIsNotRunning() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        channel.fail(.handshake(status: 502))
        try await harness.states.wait(for: .waitingToRetry(.daemonNotRunning))
    }

    @Test func networkFailureMeansNoConnection() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        channel.fail(.network)
        try await harness.states.wait(for: .waitingToRetry(.unreachable))
    }

    @Test func failedPairingAttemptReturnsToPairingWithTheProblem() async throws {
        let harness = Harness()
        await harness.manager.pair(ConnectionFixtures.link)
        let channel = try await harness.transport.channel(0)
        channel.fail(.handshake(status: 502))
        try await harness.states.wait(for: .pairingRequired(.daemonNotRunning))
        #expect(harness.clock.sleeperCount == 0)
    }

    @Test func backoffGrowsIsCappedAndResetsWhenAConnectionOpens() async throws {
        let jitters = JitterSequence([0.8, 1.2, 1.2, 1.2, 1.2, 1.2, 1.0])
        let harness = Harness(credential: ConnectionFixtures.credential, jitter: { jitters.next() })
        await harness.manager.start()
        var delays: [Duration] = []
        for index in 0..<6 {
            let channel = try await harness.transport.channel(index)
            channel.fail(.network)
            let delay = try await harness.pendingRetryDelay()
            delays.append(delay)
            harness.clock.advance(by: delay)
        }
        #expect(delays == [.milliseconds(400), .milliseconds(1200), .milliseconds(2400), .milliseconds(4800), .seconds(8), .seconds(8)])
        let opened = try await harness.connect(channel: 6)
        opened.fail(.network)
        try await harness.states.wait(for: .waitingToRetry(.unreachable))
        let delayAfterOpen = try await harness.pendingRetryDelay()
        #expect(delayAfterOpen == .milliseconds(500))
    }

    @Test func heartbeatDeclaresADeadConnectionWithinFifteenToTwentySecondsAndReopens() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential, answersPings: false)
        await harness.manager.start()
        let channel = try await harness.connect()
        try await harness.clock.waitForSleepers()
        while channel.closedAt == nil {
            #expect(harness.clock.now < .seconds(30))
            harness.clock.advance(by: .seconds(1))
            try await harness.clock.waitForSleepers()
        }
        let firstPing = try #require(channel.pingTimes.first)
        let deadAfter = try #require(channel.closedAt) - firstPing
        #expect(deadAfter >= .seconds(15))
        #expect(deadAfter <= .seconds(20))
        #expect(channel.pingTimes.count >= 3)
        try await harness.states.wait(for: .waitingToRetry(.unreachable))
        harness.clock.advance(by: try await harness.pendingRetryDelay())
        _ = try await harness.connect(channel: 1)
        #expect(harness.transport.channelCount == 2)
    }

    @Test func heartbeatKeepsAConnectionThatAnswersPings() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential, answersPings: true)
        await harness.manager.start()
        let channel = try await harness.connect()
        for _ in 0..<60 {
            try await harness.clock.waitForSleepers()
            harness.clock.advance(by: .seconds(1))
        }
        try await waitUntil { channel.pingTimes.count == 12 }
        #expect(channel.closeCode == nil)
        #expect(harness.states.last == .connected)
        #expect(harness.transport.channelCount == 1)
    }

    @Test func satisfiedPathRetriesRightAway() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        try await waitUntil { harness.path.subscriberCount == 1 }
        harness.path.send(NetworkPathUpdate(isSatisfied: false, interfaces: []))
        let channel = try await harness.transport.channel(0)
        channel.fail(.network)
        try await harness.states.wait(for: .waitingToRetry(.unreachable))
        harness.path.send(NetworkPathUpdate(isSatisfied: true, interfaces: ["en0"]))
        _ = try await harness.transport.channel(1)
        #expect(harness.clock.now == .zero)
    }

    @Test func pathChangeSendsAPingWithoutClosingTheConnection() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        try await waitUntil { harness.path.subscriberCount == 1 }
        harness.path.send(NetworkPathUpdate(isSatisfied: true, interfaces: ["en0"]))
        let channel = try await harness.connect()
        harness.path.send(NetworkPathUpdate(isSatisfied: true, interfaces: ["pdp_ip0"]))
        try await waitUntil { channel.pingTimes.count == 1 }
        #expect(channel.closeCode == nil)
        #expect(harness.states.last == .connected)
    }

    @Test func stopClosesWithGoingAwayAndStartReopens() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.connect()
        await harness.manager.stop()
        #expect(channel.closeCode == .goingAway)
        try await harness.states.wait(for: .idle)
        await harness.manager.start()
        _ = try await harness.connect(channel: 1)
    }

    @Test func stopDuringBackoffCancelsTheRetry() async throws {
        let harness = Harness(credential: ConnectionFixtures.credential)
        await harness.manager.start()
        let channel = try await harness.transport.channel(0)
        channel.fail(.network)
        try await harness.states.wait(for: .waitingToRetry(.unreachable))
        await harness.manager.stop()
        try await harness.states.wait(for: .idle)
        harness.clock.advance(by: .seconds(10))
        try await Task.sleep(for: .milliseconds(20))
        #expect(harness.transport.channelCount == 1)
    }
}

final class JitterSequence: Sendable {
    private let values: Mutex<[Double]>

    init(_ values: [Double]) {
        self.values = Mutex(values)
    }

    func next() -> Double {
        values.withLock { $0.isEmpty ? 1 : $0.removeFirst() }
    }
}
