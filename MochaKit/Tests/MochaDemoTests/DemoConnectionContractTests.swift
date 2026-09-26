import Foundation
import MochaProtocol
import Testing
@testable import MochaDemo

private func link() throws -> PairingLink {
    PairingLink(url: try #require(URL(string: "wss://mac-de-demonstracao.tail.ts.net/v1")), code: "q1W-e2R_t3Y")
}

@Suite(.timeLimit(.minutes(1)))
struct DemoConnectionContractTests {
    @Test func statesStartIdleAndStartConnectsWithHelloOkAndTree() async throws {
        let harness = try DemoHarness()
        #expect(try await harness.states.next() == .idle)

        await harness.connection.start()

        #expect(try await harness.states.next() == .connecting)
        #expect(try await harness.states.next() == .connected)
        let helloOk = try await harness.messages.next()
        #expect(helloOk.id == "hello-1")
        guard case .helloOk(let payload) = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        #expect(payload.deviceToken == nil)
        #expect(payload.host == DemoServerConnection.host)
        #expect(payload.preferences == DevicePreferences(turnDoneAlerts: true))
        let tree = try await harness.messages.next()
        #expect(tree.id == "hello-1")
        #expect(tree.message == .tree(workspaces: try DemoDataset.bundled().workspaces))
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func sendThrowsNotConnectedUntilTheHandshakeEnds() async throws {
        let harness = try DemoHarness(DemoOptions(connectDelay: .seconds(30)))

        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-1")
        }
        await harness.connection.start()
        #expect(try await harness.states.next() == .idle)
        #expect(try await harness.states.next() == .connecting)
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-2")
        }
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func startIsIdempotent() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        await harness.connection.start()
        await harness.connection.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await harness.states.unread().isEmpty)
        #expect(await harness.messages.unread().isEmpty)
    }

    @Test func stopGoesIdleCancelsThePendingHandshakeAndStartOpensANewConnection() async throws {
        let harness = try DemoHarness(DemoOptions(connectDelay: .milliseconds(150)))
        #expect(try await harness.states.next() == .idle)
        await harness.connection.start()
        #expect(try await harness.states.next() == .connecting)

        await harness.connection.stop()

        #expect(try await harness.states.next() == .idle)
        try await Task.sleep(for: .milliseconds(300))
        #expect(await harness.messages.unread().isEmpty)
        #expect(await harness.states.unread().isEmpty)

        await harness.connection.start()
        #expect(try await harness.states.next() == .connecting)
        #expect(try await harness.states.next() == .connected)
        #expect(try await harness.messages.next().id == "hello-1")
        #expect(try await harness.messages.next().id == "hello-1")

        await harness.connection.stop()
        #expect(try await harness.states.next() == .idle)
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-1")
        }

        await harness.connection.start()
        #expect(try await harness.states.next() == .connecting)
        #expect(try await harness.states.next() == .connected)
        let helloOk = try await harness.messages.next()
        #expect(helloOk.id == "hello-2")
        guard case .helloOk = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
    }

    @Test func pairingFromPairingRequiredReturnsADeviceToken() async throws {
        let harness = try DemoHarness(DemoOptions(startsPaired: false, connectDelay: .milliseconds(5)))
        #expect(try await harness.states.next() == .idle)

        await harness.connection.start()
        #expect(try await harness.states.next() == .pairingRequired(nil))
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-1")
        }
        await harness.connection.start()

        await harness.connection.pair(try link())

        #expect(try await harness.states.next() == .connecting)
        #expect(try await harness.states.next() == .connected)
        let helloOk = try await harness.messages.next()
        #expect(helloOk.id == "hello-1")
        guard case .helloOk(let payload) = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        #expect(payload.deviceToken == DemoServerConnection.deviceToken)
        let tree = try await harness.messages.next()
        #expect(tree.id == "hello-1")
        guard case .tree = tree.message else { throw UnexpectedMessage(envelope: tree) }
        #expect(await harness.states.unread().isEmpty)
    }

    @Test func unpairAcksAndThenRequiresPairing() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let ack = try await harness.request(.unpair)

        #expect(ack.message == .ack())
        #expect(try await harness.states.next() == .pairingRequired(nil))
        await #expect(throws: ServerConnectionError.notConnected) {
            try await harness.connection.send(.ping, id: "c-1")
        }
        await harness.connection.start()
        #expect(await harness.states.unread().isEmpty)

        await harness.connection.stop()
        #expect(try await harness.states.next() == .idle)
        await harness.connection.start()
        #expect(try await harness.states.next() == .pairingRequired(nil))

        await harness.connection.pair(try link())
        #expect(try await harness.states.next() == .connecting)
        #expect(try await harness.states.next() == .connected)
        let helloOk = try await harness.messages.next()
        #expect(helloOk.id == "hello-2")
        guard case .helloOk(let payload) = helloOk.message else { throw UnexpectedMessage(envelope: helloOk) }
        #expect(payload.deviceToken == DemoServerConnection.deviceToken)
    }

    @Test func helloThroughSendIsRejectedAsARepeatedHello() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        let error = try await harness.error(
            for: .hello(HelloPayload(deviceToken: "token", deviceName: "iPhone de teste", appVersion: "0.1.0"))
        )

        #expect(error.code == .invalidPayload)
        #expect(error.message == DemoServerConnection.repeatedHelloMessage)
        #expect(await harness.states.unread().isEmpty)
    }

    @Test func responsesRepeatTheIdChosenByTheCaller() async throws {
        let harness = try DemoHarness()
        try await harness.connect()

        try await harness.connection.send(.ping, id: "c-7")

        let pong = try await harness.messages.next()
        #expect(pong.id == "c-7")
        #expect(pong.message == .pong)
    }
}
