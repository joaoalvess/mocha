import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubHelloTests {
    @Test func pairingReturnsATokenThatReconnects() async throws {
        try await withHub { harness in
            let (first, paired) = try await harness.pairedClient(name: "iPhone do João")
            let token = try #require(paired.deviceToken)
            #expect(paired.host == HostInfo(hostName: "Mac de Teste", daemonVersion: "9.9.9", herdrConnected: true))
            #expect(paired.preferences == DevicePreferences(turnDoneAlerts: true))
            first.disconnect()

            let second = harness.connect()
            let helloOk = try await second.request(.hello(HelloPayload(deviceToken: token, deviceName: "iPhone do João", appVersion: "1.0")), id: "hello-2")
            #expect(helloOk.id == "hello-2")
            guard case .helloOk(let reconnected) = helloOk.message else { throw UnexpectedMessage(message: helloOk.message) }
            #expect(reconnected.deviceId == paired.deviceId)
            #expect(reconnected.deviceToken == nil)
            let tree = try await second.next()
            #expect(tree.id == "hello-2")
            #expect(tree.message == .tree(workspaces: Sample.defaultTree))

            let stored = try await harness.devices.devices()
            #expect(stored.map(\.id) == [paired.deviceId])
            #expect(stored.first?.name == "iPhone do João")
        }
    }

    @Test func versionIsCheckedBeforeEverythingElse() async throws {
        try await withHub { harness in
            let socket = harness.connect()
            socket.deliverRaw(#"{"v":1,"id":"hello-1","type":"hello","payload":{"deviceName":"x","appVersion":"1"}}"#)
            let reply = try await socket.next()
            #expect(reply.id == "hello-1")
            #expect(reply.message.errorCode == .protocolMismatch)
            #expect(try await socket.waitForClose() == .protocolError)
        }
    }

    @Test func firstMessageThatIsNotHelloIsUnauthorizedAndCloses() async throws {
        try await withHub { harness in
            let socket = harness.connect()
            let reply = try await socket.request(.ping, id: "c-1")
            #expect(reply.id == "c-1")
            #expect(reply.message.errorCode == .unauthorized)
            #expect(try await socket.waitForClose() == .policyViolation)
        }
    }

    @Test func garbageBeforeHelloIsUnauthorizedAndCloses() async throws {
        try await withHub { harness async throws in
            let socket = harness.connect()
            socket.deliverRaw("não é json")
            #expect(try await socket.nextMessage().errorCode == .unauthorized)
            #expect(try await socket.waitForClose() == .policyViolation)
        }
    }

    @Test func wrongTokenIsUnauthorizedAndTheThirdFailureCloses() async throws {
        try await withHub { harness async throws in
            let socket = harness.connect()
            let hello = ClientMessage.hello(HelloPayload(deviceToken: "errado", deviceName: "iPhone", appVersion: "1.0"))
            #expect(try await socket.reply(to: hello, id: "hello-1").errorCode == .unauthorized)
            #expect(try await socket.reply(to: hello, id: "hello-2").errorCode == .unauthorized)
            #expect(socket.closeCode == nil)
            #expect(try await socket.reply(to: hello, id: "hello-3").errorCode == .unauthorized)
            #expect(try await socket.waitForClose() == .policyViolation)
        }
    }

    @Test func everyRefusedHelloCountsTowardsTheThreeFailures() async throws {
        try await withHub { harness async throws in
            let socket = harness.connect()
            #expect(try await socket.reply(to: .hello(HelloPayload(pairingCode: "nunca-emitido", deviceName: "iPhone", appVersion: "1.0"))).errorCode == .pairingExpired)
            #expect(try await socket.reply(to: .hello(HelloPayload(deviceName: "iPhone", appVersion: "1.0"))).errorCode == .invalidPayload)
            #expect(socket.closeCode == nil)
            #expect(try await socket.reply(to: .hello(HelloPayload(deviceToken: "errado", deviceName: "iPhone", appVersion: "1.0"))).errorCode == .unauthorized)
            #expect(try await socket.waitForClose() == .policyViolation)
        }
    }

    @Test func expiredUsedAndUnknownCodesArePairingExpired() async throws {
        try await withHub { harness in
            let used = await harness.pairing.issueCode(url: Sample.pairingURL)
            let first = harness.connect()
            guard case .helloOk = try await first.reply(to: .hello(HelloPayload(pairingCode: used.code, deviceName: "iPhone", appVersion: "1.0"))) else {
                Issue.record("pairing failed")
                return
            }
            let second = harness.connect()
            #expect(try await second.reply(to: .hello(HelloPayload(pairingCode: used.code, deviceName: "iPhone", appVersion: "1.0"))).errorCode == .pairingExpired)

            let expired = await harness.pairing.issueCode(url: Sample.pairingURL)
            harness.clock.advance(by: .seconds(600))
            let third = harness.connect()
            #expect(try await third.reply(to: .hello(HelloPayload(pairingCode: expired.code, deviceName: "iPhone", appVersion: "1.0"))).errorCode == .pairingExpired)
            #expect(try await harness.devices.devices().count == 1)
        }
    }

    @Test func helloWithBothCredentialsIsInvalidPayload() async throws {
        try await withHub { harness in
            let code = await harness.pairing.issueCode(url: Sample.pairingURL)
            let socket = harness.connect()
            let reply = try await socket.reply(to: .hello(HelloPayload(deviceToken: "a", pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0")))
            #expect(reply.errorCode == .invalidPayload)
        }
    }

    @Test func repeatedHelloIsInvalidPayloadAndKeepsTheConnection() async throws {
        try await withHub { harness in
            let (socket, paired) = try await harness.pairedClient()
            let token = try #require(paired.deviceToken)
            let reply = try await socket.reply(to: .hello(HelloPayload(deviceToken: token, deviceName: "iPhone", appVersion: "1.0")), id: "c-2")
            #expect(reply.errorCode == .invalidPayload)
            #expect(try await socket.reply(to: .ping, id: "c-3") == .pong)
        }
    }

    @Test func helloOkReportsTheHerdrStateAtHelloTime() async throws {
        try await withHub(available: false) { harness in
            let (_, helloOk) = try await harness.pairedClient()
            #expect(helloOk.host.herdrConnected == false)
        }
    }

    @Test func eventsReachOnlyAuthenticatedClients() async throws {
        try await withHub { harness in
            let (paired, _) = try await harness.pairedClient()
            let anonymous = harness.connect()
            harness.herdr.setAvailable(false)
            #expect(try await paired.nextMessage() == .herdrStatus(connected: false))
            #expect(anonymous.pendingCount == 0)
            #expect(try await anonymous.reply(to: .ping).errorCode == .unauthorized)
        }
    }
}

extension ServerMessage {
    var errorCode: ProtocolErrorCode? {
        guard case .error(let code, _) = self else { return nil }
        return code
    }

    var errorMessage: String? {
        guard case .error(_, let message) = self else { return nil }
        return message
    }
}
