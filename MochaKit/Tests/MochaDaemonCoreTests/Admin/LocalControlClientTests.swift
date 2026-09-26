import Foundation
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LocalControlClientTests {
    static func leaveStaleSocket(at path: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0)
    }

    static func withServer(_ router: HttpRouter, _ body: (String) async throws -> Void) async throws {
        let path = FakeHerdrServer.temporarySocketPath()
        let server = HttpServer(binding: .unixSocket(path: path), router: router)
        try await server.start()
        do {
            try await body(path)
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    @Test func missingSocketMeansTheDaemonIsStopped() async throws {
        let client = LocalControlClient(socketPath: FakeHerdrServer.temporarySocketPath())
        await #expect(throws: LocalControlError.notRunning) { try await client.status() }
        await #expect(throws: LocalControlError.notRunning) { try await client.pairingCode() }
        await #expect(throws: LocalControlError.notRunning) { try await client.removeDevice("abc") }
    }

    @Test func staleSocketMeansTheDaemonIsStopped() async throws {
        let path = FakeHerdrServer.temporarySocketPath()
        defer { unlink(path) }
        try Self.leaveStaleSocket(at: path)
        #expect(socketMode(path)?.isSocket == true)

        await #expect(throws: LocalControlError.notRunning) {
            try await LocalControlClient(socketPath: path).status()
        }
    }

    @Test func regularFileIsNotADaemon() async throws {
        let path = FakeHerdrServer.temporarySocketPath()
        defer { unlink(path) }
        #expect(FileManager.default.createFile(atPath: path, contents: Data("x".utf8)))
        await #expect(throws: LocalControlError.notRunning) {
            try await LocalControlClient(socketPath: path).status()
        }
    }

    @Test func slowDaemonTimesOut() async throws {
        var router = HttpRouter()
        router.route(.get, LocalControl.statusPath) { _ in
            try await Task.sleep(for: .seconds(5))
            return HttpResponse()
        }
        try await Self.withServer(router) { path in
            let started = ContinuousClock.now
            await #expect(throws: LocalControlError.timedOut) {
                try await LocalControlClient(socketPath: path, timeout: .milliseconds(300)).status()
            }
            #expect(ContinuousClock.now - started < .seconds(3))
        }
    }

    @Test func responseAfterASlowHandlerIsRead() async throws {
        var router = HttpRouter()
        router.route(.get, LocalControl.statusPath) { _ in
            try await Task.sleep(for: .milliseconds(600))
            return HttpResponse(headers: ["Content-Type": "application/json"], body: Data(#"{"ok":true}"#.utf8))
        }
        try await Self.withServer(router) { path in
            for _ in 0..<3 {
                let response = try await LocalControlClient(socketPath: path).send(.get, LocalControl.statusPath)
                #expect(response == LocalControlResponse(status: 200, body: Data(#"{"ok":true}"#.utf8)))
            }
        }
    }

    @Test func errorBodyBecomesTheMessage() async throws {
        var router = HttpRouter()
        router.route(.post, LocalControl.pairingCodePath) { _ in
            HttpResponse(status: .internalServerError, headers: ["Content-Type": "application/json"], body: Data(#"{"error":"deu ruim"}"#.utf8))
        }
        try await Self.withServer(router) { path in
            await #expect(throws: LocalControlError.unexpectedStatus(500, "deu ruim")) {
                try await LocalControlClient(socketPath: path).pairingCode()
            }
        }
    }

    @Test func parseHonorsContentLengthAndRejectsGarbage() throws {
        let response = try LocalControlClient.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}extra".utf8))
        #expect(response == LocalControlResponse(status: 200, body: Data("{}".utf8)))
        #expect(throws: LocalControlError.invalidResponse) {
            try LocalControlClient.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n{}".utf8))
        }
        #expect(throws: LocalControlError.invalidResponse) {
            try LocalControlClient.parse(Data("SSH-2.0-OpenSSH\r\n".utf8))
        }
    }
}
