import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionHubControlTests {
    @Test func connectedClientsListsAuthenticatedConnections() async throws {
        try await withHub { harness in
            #expect(await harness.hub.connectedClients().isEmpty)
            let (first, firstHello) = try await harness.pairedClient(name: "iPhone do João")
            let (_, secondHello) = try await harness.pairedClient(name: "iPad")
            let anonymous = harness.connect()
            #expect(try await anonymous.reply(to: .hello(HelloPayload(deviceToken: "errado", deviceName: "x", appVersion: "1"))).errorCode == .unauthorized)

            let connected = await harness.hub.connectedClients()
            #expect(Set(connected.map(\.deviceId)) == [firstHello.deviceId, secondHello.deviceId])
            #expect(Set(connected.map(\.name)) == ["iPhone do João", "iPad"])
            #expect(connected.allSatisfy { $0.connectedAt == Sample.start })

            first.disconnect()
            let remaining = try await eventually {
                let clients = await harness.hub.connectedClients()
                return clients.count == 1 ? clients : nil
            }
            #expect(remaining.map(\.deviceId) == [secondHello.deviceId])
        }
    }

    @Test func followedSessionsListsOpenChats() async throws {
        let archived = TranscriptMeta(title: "arquivada")
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(archived, forSession: Sample.sessionC)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            #expect(await harness.hub.followedSessions().isEmpty)
            _ = try await socket.reply(to: .openChat(target: .agent("w1:p1")), id: "c-1")
            _ = try await socket.reply(to: .openChat(target: .session(Sample.sessionC)), id: "c-2")
            #expect(await harness.hub.followedSessions() == [
                FollowedSession(sessionId: Sample.sessionA, agentId: "w1:p1"),
                FollowedSession(sessionId: Sample.sessionC, agentId: nil),
            ])

            #expect(try await socket.reply(to: .closeChat(target: .agent("w1:p1")), id: "c-3") == .ack())
            #expect(await harness.hub.followedSessions() == [FollowedSession(sessionId: Sample.sessionC, agentId: nil)])

            socket.disconnect()
            _ = try await eventually { await harness.hub.followedSessions().isEmpty ? true : nil }
            await harness.transcripts.waitForSubscribers(0, forSession: Sample.sessionC)
        }
    }

    @Test func sessionChatOfAnAgentInTheTreeReportsTheAgent() async throws {
        try await withHub(configure: { transcripts in
            await transcripts.setMeta(TranscriptMeta(title: "atual"), forSession: Sample.sessionA)
        }) { harness in
            let (socket, _) = try await harness.pairedClient()
            _ = try await socket.reply(to: .openChat(target: .session(Sample.sessionA)))
            #expect(await harness.hub.followedSessions() == [FollowedSession(sessionId: Sample.sessionA, agentId: "w1:p1")])
        }
    }

    @Test func removeDeviceClosesItsConnectionsAndForgetsIt() async throws {
        try await withHub { harness in
            let (socket, helloOk) = try await harness.pairedClient()
            let token = try #require(helloOk.deviceToken)
            let other = try await harness.client(token: token)
            let (bystander, bystanderHello) = try await harness.pairedClient(name: "iPad")

            #expect(try await harness.hub.removeDevice(helloOk.deviceId))
            #expect(try await socket.nextMessage().errorCode == .unauthorized)
            #expect(socket.closeCode == .policyViolation)
            #expect(try await other.nextMessage().errorCode == .unauthorized)
            #expect(other.closeCode == .policyViolation)
            #expect(bystander.closeCode == nil)

            #expect(try await harness.devices.devices().map(\.id) == [bystanderHello.deviceId])
            let file = try String(contentsOf: harness.directory.appending(path: "devices.json"), encoding: .utf8)
            #expect(!file.contains(helloOk.deviceId))
            #expect(await harness.hub.connectedClients().map(\.deviceId) == [bystanderHello.deviceId])

            let again = harness.connect()
            #expect(try await again.reply(to: .hello(HelloPayload(deviceToken: token, deviceName: "iPhone", appVersion: "1.0"))).errorCode == .unauthorized)
            #expect(try await harness.hub.removeDevice("desconhecido") == false)
        }
    }
}
