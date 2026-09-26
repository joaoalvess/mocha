import Foundation
import Testing
@testable import MochaDaemonCore

struct ServerSideClose: Sendable, Equatable {
    let code: WebSocketCloseCode?
    let reason: String?
}

final class WebSocketTaskEvents: NSObject, URLSessionWebSocketDelegate, Sendable {
    let opened = TestSignal<Void>()
    let closed = TestSignal<Int>()

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        opened.fire()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        closed.fire(closeCode.rawValue)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct WebSocketSessionTests {
    private static func echoRouter(serverSideClose: TestSignal<ServerSideClose>? = nil) -> HttpRouter {
        var router = HttpRouter()
        router.webSocket("/ws") { _, socket in
            try? await socket.send(text: "welcome")
            for await message in socket.messages {
                switch message {
                case .text("server-close"):
                    await socket.close(code: .goingAway, reason: "bye")
                case .text(let text):
                    try? await socket.send(text: "echo:" + text)
                case .binary(let data):
                    try? await socket.send(binary: Data(data.reversed()))
                }
            }
            serverSideClose?.fire(ServerSideClose(code: await socket.closeCode, reason: await socket.closeReason))
        }
        return router
    }

    private static func openTask(
        port: UInt16,
        events: WebSocketTaskEvents
    ) async throws -> (session: URLSession, task: URLSessionWebSocketTask) {
        let session = URLSession(configuration: .ephemeral, delegate: events, delegateQueue: nil)
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/ws"))
        let task = session.webSocketTask(with: url)
        task.resume()
        try await events.opened.wait()
        return (session, task)
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

    private static func ping(_ task: URLSessionWebSocketTask) async throws {
        try await withTimeout {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    task.sendPing { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } onCancel: {
                task.cancel()
            }
        }
    }

    @Test func handshakeAndMessagesInBothDirections() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let events = WebSocketTaskEvents()
            let (session, task) = try await Self.openTask(port: port, events: events)
            defer { session.invalidateAndCancel() }
            #expect(try await Self.receive(task) == .text("welcome"))
            try await task.send(.string("olá, mocha"))
            #expect(try await Self.receive(task) == .text("echo:olá, mocha"))
            try await task.send(.data(Data([1, 2, 3])))
            #expect(try await Self.receive(task) == .binary(Data([3, 2, 1])))
            let large = String(repeating: "x", count: 100_000)
            try await task.send(.string(large))
            #expect(try await Self.receive(task) == .text("echo:" + large))
            task.cancel(with: .normalClosure, reason: nil)
        }
    }

    @Test func pingIsAnsweredWithPong() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let events = WebSocketTaskEvents()
            let (session, task) = try await Self.openTask(port: port, events: events)
            defer { session.invalidateAndCancel() }
            #expect(try await Self.receive(task) == .text("welcome"))
            let pendingReceive = Task { try await task.receive() }
            try await Self.ping(task)
            try await Self.ping(task)
            task.cancel(with: .normalClosure, reason: nil)
            _ = await pendingReceive.result
        }
    }

    @Test func clientCloseReachesHandlerAndIsEchoed() async throws {
        let serverSideClose = TestSignal<ServerSideClose>()
        try await withRunningServer(Self.echoRouter(serverSideClose: serverSideClose)) { port in
            let events = WebSocketTaskEvents()
            let (session, task) = try await Self.openTask(port: port, events: events)
            defer { session.invalidateAndCancel() }
            #expect(try await Self.receive(task) == .text("welcome"))
            task.cancel(with: .normalClosure, reason: Data("bye".utf8))
            #expect(try await serverSideClose.wait() == ServerSideClose(code: .normalClosure, reason: "bye"))
            #expect(try await events.closed.wait() == URLSessionWebSocketTask.CloseCode.normalClosure.rawValue)
        }
    }

    @Test func serverCloseReachesClient() async throws {
        try await withRunningServer(Self.echoRouter()) { port in
            let events = WebSocketTaskEvents()
            let (session, task) = try await Self.openTask(port: port, events: events)
            defer { session.invalidateAndCancel() }
            #expect(try await Self.receive(task) == .text("welcome"))
            try await task.send(.string("server-close"))
            await #expect(throws: (any Error).self) {
                try await Self.receive(task)
            }
            #expect(try await events.closed.wait() == URLSessionWebSocketTask.CloseCode.goingAway.rawValue)
            #expect(task.closeCode == .goingAway)
            #expect(task.closeReason == Data("bye".utf8))
        }
    }
}
