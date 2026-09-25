import CryptoKit
import Foundation
import Testing
@testable import MochaDaemonCore

struct RecordedClose: Sendable, Equatable {
    let code: WebSocketCloseCode?
    let reason: String?
    let messages: Int
}

@Suite(.timeLimit(.minutes(1)))
struct GatewayTests {
    @Test func healthReportsVersionAndHerdrState() async throws {
        let gateway = Gateway(version: "9.9.9", herdrAvailable: { true })
        try await withRunningServer(gateway.makeRouter()) { port in
            let response = try await sendRequest("GET", port: port, target: "/v1/health")
            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "application/json")
            let health = try JSONDecoder().decode(GatewayHealth.self, from: response.body)
            #expect(health == GatewayHealth(ok: true, version: "9.9.9", herdr: true))
        }
    }

    @Test func healthDefaultsToDaemonVersionWithoutHerdr() async throws {
        try await withRunningServer(Gateway().makeRouter()) { port in
            let response = try await sendRequest("GET", port: port, target: "/v1/health")
            let health = try JSONDecoder().decode(GatewayHealth.self, from: response.body)
            #expect(health == GatewayHealth(ok: true, version: DaemonVersion.current, herdr: false))
        }
    }

    @Test func webSocketEchoesAndReportsLifecycle() async throws {
        let (events, continuation) = AsyncStream.makeStream(of: GatewayEvent.self)
        let gateway = Gateway(events: { continuation.yield($0) })
        try await withRunningServer(gateway.makeRouter()) { port in
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/v1?probe=1"))
            let task = session.webSocketTask(with: url)
            task.resume()
            try await task.send(.string("{\"seq\":1}"))
            #expect(try await Self.receive(task) == .text("{\"seq\":1}"))
            try await task.send(.data(Data([1, 2, 3])))
            #expect(try await Self.receive(task) == .binary(Data([1, 2, 3])))
            task.cancel(with: .normalClosure, reason: Data("fim".utf8))
            let (openedQuery, close) = try await withTimeout {
                var query: String?
                for await event in events {
                    switch event {
                    case .webSocketOpened(_, let request):
                        query = request.query
                    case .webSocketClosed(_, let code, let reason, let messages, _):
                        return (query, RecordedClose(code: code, reason: reason, messages: messages))
                    case .httpRequest, .webSocketMessage:
                        continue
                    }
                }
                throw TestTimeoutError()
            }
            #expect(openedQuery == "probe=1")
            #expect(close == RecordedClose(code: .normalClosure, reason: "fim", messages: 2))
        }
    }

    @Test func spikeRoutesAreOptIn() async throws {
        try await withRunningServer(Gateway().makeRouter()) { port in
            let response = try await sendRequest("GET", port: port, target: Gateway.spikeEchoPath)
            #expect(response.status == 404)
        }
    }

    @Test func spikeEchoReportsQueryHeadersAndBody() async throws {
        let gateway = Gateway()
        var router = gateway.makeRouter()
        gateway.addSpikeRoutes(to: &router)
        let body = Data((0..<50_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        try await withRunningServer(router) { port in
            let response = try await sendRequest(
                "POST",
                port: port,
                target: "/spike/echo?code=a%2Fb&x=",
                headers: ["Authorization": "Bearer teste"],
                body: body
            )
            #expect(response.status == 200)
            let echo = try JSONDecoder().decode(GatewaySpikeEcho.self, from: response.body)
            #expect(echo.method == "POST")
            #expect(echo.query == "code=a%2Fb&x=")
            #expect(echo.bodyBytes == body.count)
            #expect(echo.bodySha256 == SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined())
            #expect(echo.headers.contains(["Authorization", "Bearer teste"]))
            #expect(echo.headers.contains { $0.first?.lowercased() == "content-length" && $0.last == "50000" })
        }
    }

    private static func receive(_ task: URLSessionWebSocketTask) async throws -> WebSocketMessage {
        try await withTimeout {
            try await withTaskCancellationHandler {
                switch try await task.receive() {
                case .string(let text): .text(text)
                case .data(let data): .binary(data)
                @unknown default: .binary(Data())
                }
            } onCancel: {
                task.cancel()
            }
        }
    }
}
