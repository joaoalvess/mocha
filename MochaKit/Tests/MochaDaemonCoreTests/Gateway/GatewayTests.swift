import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct GatewayTests {
    private static let textOpcode: UInt8 = 0x1
    private static let closeOpcode: UInt8 = 0x8

    @Test func bindsOnlyToLoopbackOnTheGatewayPort() {
        #expect(Gateway.binding == .loopback(port: 47421))
        #expect(Gateway.healthPath == "/v1/health")
        #expect(Gateway.webSocketPath == "/v1")
    }

    @Test(arguments: [true, false])
    func healthReportsVersionAndHerdrAvailability(available: Bool) async throws {
        try await withHub(available: available) { harness in
            let gateway = Gateway(version: "9.9.9", herdr: harness.herdr, hub: harness.hub)
            try await withRunningServer(gateway.makeRouter()) { port in
                let response = try await sendRequest("GET", port: port, target: "/v1/health")
                #expect(response.status == 200)
                #expect(response.header("Content-Type") == "application/json")
                let health = try JSONDecoder().decode(GatewayHealth.self, from: response.body)
                #expect(health == GatewayHealth(ok: true, version: "9.9.9", herdr: available))

                harness.herdr.setAvailable(!available)
                let changed = try await sendRequest("GET", port: port, target: "/v1/health")
                #expect(try JSONDecoder().decode(GatewayHealth.self, from: changed.body).herdr == !available)
            }
        }
    }

    @Test func pairReconnectAndFollowAChatOverTheSocket() async throws {
        let first = Sample.item("i1", text: "primeira")
        try await withHub(configure: { transcripts in
            await transcripts.setPage(Sample.page([first]), forSession: Sample.sessionA)
        }) { harness in
            let gateway = Gateway(version: "9.9.9", herdr: harness.herdr, hub: harness.hub)
            try await withRunningServer(gateway.makeRouter()) { port in
                let code = await harness.pairing.issueCode(url: Sample.pairingURL)
                let pairing = try await Self.open(port)
                try await Self.send(.hello(HelloPayload(pairingCode: code.code, deviceName: "iPhone do João", appVersion: "1.0")), id: "hello-1", to: pairing)
                let paired = try await Self.receive(pairing)
                #expect(paired.id == "hello-1")
                guard case .helloOk(let helloOk) = paired.message else { throw UnexpectedMessage(message: paired.message) }
                let token = try #require(helloOk.deviceToken)
                #expect(try await Self.receive(pairing).message == .tree(workspaces: Sample.defaultTree))
                #expect(try await Self.receive(pairing).message == .archived(sessions: []))
                try await pairing.send(RawFrameBuilder.close(code: 1000))
                #expect(try await Self.nextFrame(pairing).closeCode == 1000)
                pairing.cancel()

                let client = try await Self.open(port)
                try await Self.send(.hello(HelloPayload(deviceToken: token, deviceName: "iPhone do João", appVersion: "1.0")), id: "hello-2", to: client)
                let reconnected = try await Self.receive(client)
                guard case .helloOk(let again) = reconnected.message else { throw UnexpectedMessage(message: reconnected.message) }
                #expect(again.deviceId == helloOk.deviceId)
                #expect(again.deviceToken == nil)
                let tree = try await Self.receive(client)
                #expect(tree.id == "hello-2")
                #expect(tree.message == .tree(workspaces: Sample.defaultTree))
                #expect(try await Self.receive(client).message == .archived(sessions: []))

                try await Self.send(.openChat(target: .agent("w1:p1")), id: "c-1", to: client)
                let page = try await Self.receive(client)
                #expect(page.id == "c-1")
                guard case .chatPage(let chatPage) = page.message else { throw UnexpectedMessage(message: page.message) }
                #expect(chatPage.items == [first])

                let second = Sample.item("i2", text: "segunda")
                await harness.transcripts.emit(.append([second]), toSession: Sample.sessionA)
                let append = try await Self.receive(client)
                #expect(append.id == nil)
                #expect(append.message == .chatAppend(target: .agent("w1:p1"), items: [second]))
                client.cancel()
            }
        }
    }

    @Test func threeWrongTokensClose1008() async throws {
        try await withHub { harness in
            let gateway = Gateway(version: "9.9.9", herdr: harness.herdr, hub: harness.hub)
            try await withRunningServer(gateway.makeRouter()) { port in
                let client = try await Self.open(port)
                for attempt in 1...3 {
                    try await Self.send(.hello(HelloPayload(deviceToken: "errado", deviceName: "iPhone", appVersion: "1.0")), id: "hello-\(attempt)", to: client)
                    let reply = try await Self.receive(client)
                    #expect(reply.id == "hello-\(attempt)")
                    #expect(reply.message.errorCode == .unauthorized)
                }
                let close = try await Self.nextFrame(client)
                #expect(close.opcode == Self.closeOpcode)
                #expect(close.closeCode == 1008)
                client.cancel()
            }
        }
    }

    @Test func firstMessageThatIsNotHelloCloses1008() async throws {
        try await withHub { harness in
            let gateway = Gateway(version: "9.9.9", herdr: harness.herdr, hub: harness.hub)
            try await withRunningServer(gateway.makeRouter()) { port in
                let client = try await Self.open(port)
                try await Self.send(.openChat(target: .agent("w1:p1")), id: "c-1", to: client)
                let reply = try await Self.receive(client)
                #expect(reply.id == "c-1")
                #expect(reply.message.errorCode == .unauthorized)
                #expect(try await Self.nextFrame(client).closeCode == 1008)
                #expect(await harness.transcripts.openRequests.isEmpty)
                client.cancel()
            }
        }
    }

    @Test func shutdownClosesSockets1001BeforeTheServerStops() async throws {
        try await withHub { harness in
            let (events, continuation) = AsyncStream.makeStream(of: GatewayEvent.self)
            let gateway = Gateway(version: "9.9.9", herdr: harness.herdr, hub: harness.hub, events: { continuation.yield($0) })
            try await withRunningServer(gateway.makeRouter()) { port in
                let code = await harness.pairing.issueCode(url: Sample.pairingURL)
                let client = try await Self.open(port)
                try await Self.send(.hello(HelloPayload(pairingCode: code.code, deviceName: "iPhone", appVersion: "1.0")), id: "hello-1", to: client)
                _ = try await Self.receive(client)
                _ = try await Self.receive(client)
                #expect(try await Self.receive(client).message == .archived(sessions: []))

                await gateway.shutdown()
                let close = try await Self.nextFrame(client)
                #expect(close.opcode == Self.closeOpcode)
                #expect(close.closeCode == 1001)
                try await client.send(RawFrameBuilder.close(code: 1001))
                let lifecycle = try await withTimeout {
                    var opened: [Int] = []
                    for await event in events {
                        switch event {
                        case .webSocketOpened(let connection, let request):
                            #expect(request.path == Gateway.webSocketPath)
                            opened.append(connection)
                        case .webSocketClosed(let connection, _, _, _):
                            return (opened, connection)
                        case .httpRequest:
                            continue
                        }
                    }
                    throw TestTimeoutError()
                }
                #expect(lifecycle.0 == [1])
                #expect(lifecycle.1 == 1)
                client.cancel()

                let late = try await Self.open(port)
                #expect(try await Self.nextFrame(late).closeCode == 1001)
                late.cancel()
            }
        }
    }

    private static func open(_ port: UInt16) async throws -> RawClient {
        let (client, head) = try await RawClient.openWebSocket(port: port, path: Gateway.webSocketPath)
        #expect(head.hasPrefix("HTTP/1.1 101"))
        return client
    }

    private static func send(_ message: ClientMessage, id: String, to client: RawClient) async throws {
        let data = try JSONEncoder().encode(ClientEnvelope(id: id, message: message))
        try await client.send(RawFrameBuilder.text(String(decoding: data, as: UTF8.self)))
    }

    private static func nextFrame(_ client: RawClient) async throws -> RawFrame {
        try await withTimeout {
            try await client.readFrame()
        }
    }

    private static func receive(_ client: RawClient) async throws -> ServerEnvelope {
        let frame = try await nextFrame(client)
        guard frame.opcode == textOpcode else {
            Issue.record("expected a text frame, got opcode \(frame.opcode) close \(String(describing: frame.closeCode))")
            throw TestTimeoutError()
        }
        return try JSONDecoder().decode(ServerEnvelope.self, from: Data(frame.payload))
    }
}
