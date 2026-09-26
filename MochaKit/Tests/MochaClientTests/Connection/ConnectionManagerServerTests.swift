import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaClient

@Suite(.timeLimit(.minutes(1)))
struct ConnectionManagerServerTests {
    private static let timeScale: Double = 20

    private static func makeManager(
        store: FakeTokenStore,
        transport: any WebSocketTransport = URLSessionWebSocketTransport(),
        clock: ScaledClock
    ) -> ConnectionManager {
        ConnectionManager(
            configuration: ConnectionFixtures.configuration,
            tokenStore: store,
            transport: transport,
            clock: clock,
            pathMonitor: FakePathMonitor(),
            jitter: { 1 }
        )
    }

    @Test func pairsByCodeSavesTheTokenAndReconnectsWithItAfterTheServerDrops() async throws {
        let server = TestGatewayServer()
        try await server.start()
        let url = try await server.url()
        let code = await server.hub.issuePairingCode()
        let store = FakeTokenStore()
        let clock = ScaledClock(factor: Self.timeScale)
        let manager = Self.makeManager(store: store, clock: clock)
        let states = Recorder(manager.states)
        let messages = Recorder(manager.messages)

        await manager.pair(PairingLink(url: url, code: code))
        try await states.wait(for: .connected)
        let credential = try #require(await store.credential)
        #expect(credential.url == url)
        #expect(await server.hub.tokens == [credential.token])
        try await waitUntil { messages.all.map(\.message.type) == ["helloOk", "tree"] }
        guard case .helloOk(let payload) = messages.all.first?.message else {
            Issue.record("expected helloOk first")
            return
        }
        #expect(payload.deviceToken == credential.token)
        #expect(payload.host.hostName == TestGatewayServer.hostName)

        await server.stop()
        try await states.wait(for: .waitingToRetry(.unreachable))
        try await waitUntil { clock.requestedSleeps.filter { $0 != ConnectionConfiguration.pingInterval }.count >= 4 }
        try await server.start()
        try await states.wait(for: .connected, timeout: .seconds(20))

        let retries = clock.requestedSleeps.filter { $0 != ConnectionConfiguration.pingInterval }
        #expect(Array(retries.prefix(4)) == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)])
        #expect(retries.allSatisfy { $0 <= .seconds(8) })
        let lastHello = try #require(await server.hub.hellos.last)
        #expect(lastHello.deviceToken == credential.token)
        #expect(lastHello.pairingCode == nil)
        #expect(await server.hub.hellos.first?.pairingCode == code)

        let retriesBeforeSecondDrop = retries.count
        await server.stop()
        try await states.wait(for: .waitingToRetry(.unreachable))
        try await waitUntil { clock.requestedSleeps.filter { $0 != ConnectionConfiguration.pingInterval }.count > retriesBeforeSecondDrop }
        let afterReset = clock.requestedSleeps.filter { $0 != ConnectionConfiguration.pingInterval }
        #expect(afterReset[retriesBeforeSecondDrop] == .milliseconds(500))
        await manager.stop()
    }

    @Test func badGatewayOnTheHandshakeMeansTheDaemonIsNotRunning() async throws {
        let server = TestGatewayServer()
        try await server.start()
        let url = try await server.url(path: TestGatewayServer.badGatewayPath)
        let store = FakeTokenStore(credential: DeviceCredential(url: url, token: "token"))
        let manager = Self.makeManager(store: store, clock: ScaledClock(factor: 1))
        let states = Recorder(manager.states)
        await manager.start()
        try await states.wait(for: .waitingToRetry(.daemonNotRunning))
        await manager.stop()
        await server.stop()
    }

    @Test func refusedPortMeansNoConnection() async throws {
        let server = TestGatewayServer()
        try await server.start()
        let url = try await server.url()
        await server.stop()
        let store = FakeTokenStore(credential: DeviceCredential(url: url, token: "token"))
        let manager = Self.makeManager(store: store, clock: ScaledClock(factor: 1))
        let states = Recorder(manager.states)
        await manager.start()
        try await states.wait(for: .waitingToRetry(.unreachable))
        await manager.stop()
    }

    @Test func refusedTokenAndExpiredCodeLeadToPairing() async throws {
        let server = TestGatewayServer()
        try await server.start()
        let url = try await server.url()
        let store = FakeTokenStore(credential: DeviceCredential(url: url, token: "revoked"))
        let manager = Self.makeManager(store: store, clock: ScaledClock(factor: 1))
        let states = Recorder(manager.states)
        await manager.start()
        try await states.wait(for: .pairingRequired(.unauthorized))
        #expect(await store.credential?.token == "revoked")
        await manager.pair(PairingLink(url: url, code: "never-issued"))
        try await states.wait(for: .pairingRequired(.pairingExpired))
        #expect(await store.credential?.token == "revoked")
        await manager.stop()
        await server.stop()
    }

    @Test func unpairDeletesTheTokenAndEndsInPairing() async throws {
        let server = TestGatewayServer()
        try await server.start()
        let url = try await server.url()
        await server.hub.register(token: "token")
        let store = FakeTokenStore(credential: DeviceCredential(url: url, token: "token"))
        let manager = Self.makeManager(store: store, clock: ScaledClock(factor: 1))
        let states = Recorder(manager.states)
        await manager.start()
        try await states.wait(for: .connected)
        try await manager.send(.unpair, id: "c-1")
        try await states.wait(for: .pairingRequired(nil))
        #expect(await store.credential == nil)
        #expect(await server.hub.tokens.isEmpty)
        await manager.stop()
        await server.stop()
    }

    @Test func pingsAreAnsweredByTheHttpServer() async throws {
        let server = TestGatewayServer()
        try await server.start()
        let url = try await server.url()
        await server.hub.register(token: "token")
        let store = FakeTokenStore(credential: DeviceCredential(url: url, token: "token"))
        let transport = PongCountingTransport()
        let manager = Self.makeManager(store: store, transport: transport, clock: ScaledClock(factor: Self.timeScale))
        let states = Recorder(manager.states)
        await manager.start()
        try await states.wait(for: .connected)
        try await waitUntil(timeout: .seconds(20)) { transport.pongs >= 4 }
        #expect(states.all == [.idle, .connecting, .connected])
        #expect(await server.hub.connectionCount == 1)
        await manager.stop()
        await server.stop()
    }

    @Test func serverWithoutPongIsDeclaredDeadAndReopened() async throws {
        let server = TestGatewayServer(automaticPong: false)
        try await server.start()
        let url = try await server.url()
        await server.hub.register(token: "token")
        let store = FakeTokenStore(credential: DeviceCredential(url: url, token: "token"))
        let clock = ScaledClock(factor: Self.timeScale)
        let transport = PongCountingTransport()
        let manager = Self.makeManager(store: store, transport: transport, clock: clock)
        let states = Recorder(manager.states)
        await manager.start()
        try await states.wait(for: .connected)
        let connectedAt = clock.now
        try await states.wait(for: .waitingToRetry(.unreachable), timeout: .seconds(20))
        let deadAfter = clock.now - connectedAt
        #expect(deadAfter >= .seconds(15))
        #expect(deadAfter < .seconds(30))
        #expect(transport.pongs == 0)
        try await states.wait(for: .connected, timeout: .seconds(20))
        #expect(await server.hub.connectionCount == 2)
        await manager.stop()
        await server.stop()
    }
}

final class PongCountingTransport: WebSocketTransport {
    private let base = URLSessionWebSocketTransport()
    private let counter = PongCounter()

    var pongs: Int {
        counter.value.withLock { $0 }
    }

    func connect(to url: URL) -> any WebSocketChannel {
        PongCountingChannel(base: base.connect(to: url), counter: counter)
    }
}

final class PongCounter: Sendable {
    let value = Mutex(0)
}

final class PongCountingChannel: WebSocketChannel {
    private let base: any WebSocketChannel
    private let counter: PongCounter

    init(base: any WebSocketChannel, counter: PongCounter) {
        self.base = base
        self.counter = counter
    }

    func send(_ text: String) async throws {
        try await base.send(text)
    }

    func receive() async throws -> String? {
        try await base.receive()
    }

    func sendPing(_ pongReceived: @escaping @Sendable (Bool) -> Void) {
        base.sendPing { [counter] received in
            if received {
                counter.value.withLock { $0 += 1 }
            }
            pongReceived(received)
        }
    }

    func close(_ code: URLSessionWebSocketTask.CloseCode) {
        base.close(code)
    }

    func failure(for error: any Error) -> WebSocketChannelFailure {
        base.failure(for: error)
    }
}
