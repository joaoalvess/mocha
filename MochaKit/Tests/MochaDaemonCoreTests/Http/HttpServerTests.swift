import Foundation
import Testing
@testable import MochaDaemonCore

actor InvocationCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HttpServerTests {
    @Test func getReturnsHandlerResponse() async throws {
        var router = HttpRouter()
        router.route(.get, "/hello") { _ in
            HttpResponse(headers: ["Content-Type": "text/plain", "X-Test": "1"], body: Data("hello".utf8))
        }
        try await withRunningServer(router) { port in
            let response = try await sendRequest("GET", port: port, target: "/hello")
            #expect(response.status == 200)
            #expect(String(decoding: response.body, as: UTF8.self) == "hello")
            #expect(response.header("X-Test") == "1")
            #expect(response.header("Content-Type") == "text/plain")
            #expect(response.header("Content-Length") == "5")
        }
    }

    @Test func postDeliversBodyQueryAndCaseInsensitiveHeaders() async throws {
        var router = HttpRouter()
        router.route(.post, "/echo") { request in
            HttpResponse(
                headers: [
                    "X-Query": request.query ?? "",
                    "X-Item": request.queryItems.first { $0.name == "b" }?.value ?? "",
                    "X-Seen": request.headers["x-mocha-probe"] ?? "",
                    "X-Path": request.path,
                ],
                body: request.body
            )
        }
        let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try await withRunningServer(router) { port in
            let response = try await sendRequest(
                "POST",
                port: port,
                target: "/echo?a=1&b=two",
                headers: ["X-Mocha-Probe": "yes"],
                body: payload
            )
            #expect(response.status == 200)
            #expect(response.body == payload)
            #expect(response.header("X-Query") == "a=1&b=two")
            #expect(response.header("X-Item") == "two")
            #expect(response.header("X-Seen") == "yes")
            #expect(response.header("X-Path") == "/echo")
        }
    }

    @Test func unknownPathIs404WithEmptyBody() async throws {
        var router = HttpRouter()
        router.route(.get, "/hello") { _ in HttpResponse(body: Data("hello".utf8)) }
        try await withRunningServer(router) { port in
            let response = try await sendRequest("GET", port: port, target: "/missing")
            #expect(response.status == 404)
            #expect(response.body.isEmpty)
        }
    }

    @Test func wrongMethodIs405WithEmptyBodyAndAllowHeader() async throws {
        var router = HttpRouter()
        router.route(.get, "/hello") { _ in HttpResponse(body: Data("hello".utf8)) }
        router.route(.delete, "/hello") { _ in HttpResponse() }
        try await withRunningServer(router) { port in
            let response = try await sendRequest("POST", port: port, target: "/hello", body: Data("ignored".utf8))
            #expect(response.status == 405)
            #expect(response.body.isEmpty)
            #expect(response.header("Allow") == "DELETE, GET")
        }
    }

    @Test func bodyAboveDefaultLimitIs413AndHandlerNeverRuns() async throws {
        let counter = InvocationCounter()
        var router = HttpRouter()
        router.route(.post, "/echo") { request in
            await counter.increment()
            return HttpResponse(body: request.body)
        }
        let limit = HttpServerConfiguration().defaultMaxBodySize
        try await withRunningServer(router) { port in
            let response = try await sendRequest("POST", port: port, target: "/echo", body: Data(count: limit + 1024))
            #expect(response.status == 413)
            #expect(response.body.isEmpty)
            let accepted = try await sendRequest("POST", port: port, target: "/echo", body: Data(count: limit))
            #expect(accepted.status == 200)
            #expect(accepted.body.count == limit)
        }
        #expect(await counter.count == 1)
    }

    @Test func routeLimitOverridesDefault() async throws {
        var router = HttpRouter()
        router.route(.post, "/small", maxBodySize: 64) { request in HttpResponse(body: request.body) }
        router.route(.post, "/upload", maxBodySize: 3 << 20) { request in
            HttpResponse(body: Data("\(request.body.count)".utf8))
        }
        try await withRunningServer(router) { port in
            #expect(try await sendRequest("POST", port: port, target: "/small", body: Data(count: 64)).status == 200)
            #expect(try await sendRequest("POST", port: port, target: "/small", body: Data(count: 65)).status == 413)
            let upload = try await sendRequest("POST", port: port, target: "/upload", body: Data(count: 2 << 20))
            #expect(upload.status == 200)
            #expect(String(decoding: upload.body, as: UTF8.self) == "\(2 << 20)")
        }
    }

    @Test func throwingHandlerBecomes500() async throws {
        struct Failure: Error {}
        var router = HttpRouter()
        router.route(.get, "/boom") { _ in throw Failure() }
        try await withRunningServer(router) { port in
            let response = try await sendRequest("GET", port: port, target: "/boom")
            #expect(response.status == 500)
            #expect(response.body.isEmpty)
        }
    }

    @Test func startingTwiceFails() async throws {
        let server = HttpServer(binding: .loopback(port: 0), router: HttpRouter())
        try await server.start()
        await #expect(throws: HttpServerError.alreadyStarted) {
            try await server.start()
        }
        await server.stop()
    }

    @Test func portInUseFailsToStartAndPortIsReleasedOnStop() async throws {
        let first = HttpServer(binding: .loopback(port: 0), router: HttpRouter())
        try await first.start()
        let port = try #require(await first.port)
        let second = HttpServer(binding: .loopback(port: port), router: HttpRouter())
        await #expect(throws: HttpServerError.listenerFailed(.posix(.EADDRINUSE))) {
            try await second.start()
        }
        await first.stop()
        try await second.start()
        #expect(await second.port == port)
        await second.stop()
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HttpLongHandlerTests {
    @Test func handlerHoldingResponseForFiveSecondsStillResponds() async throws {
        var router = HttpRouter()
        router.route(.get, "/slow") { _ in
            try await Task.sleep(for: .seconds(5))
            return HttpResponse(body: Data("done".utf8))
        }
        try await withRunningServer(router) { port in
            let clock = ContinuousClock()
            let start = clock.now
            let response = try await sendRequest("GET", port: port, target: "/slow")
            #expect(response.status == 200)
            #expect(String(decoding: response.body, as: UTF8.self) == "done")
            #expect(clock.now - start >= .seconds(5))
        }
    }

    @Test func clientGivingUpCancelsHandlerTask() async throws {
        let started = TestSignal<Void>()
        let outcome = TestSignal<String>()
        var router = HttpRouter()
        router.route(.get, "/hold") { _ in
            started.fire()
            do {
                try await Task.sleep(for: .seconds(50))
                outcome.fire("completed")
            } catch {
                outcome.fire(Task.isCancelled && error is CancellationError ? "cancelled" : "unexpected")
                throw error
            }
            return HttpResponse()
        }
        try await withRunningServer(router) { port in
            let session = makeTestSession()
            defer { session.invalidateAndCancel() }
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/hold"))
            let task = session.dataTask(with: url) { _, _, _ in }
            task.resume()
            try await started.wait()
            task.cancel()
            #expect(try await outcome.wait() == "cancelled")
        }
    }

    @Test func stoppingServerCancelsInFlightHandler() async throws {
        let started = TestSignal<Void>()
        let outcome = TestSignal<Bool>()
        var router = HttpRouter()
        router.route(.get, "/hold") { _ in
            started.fire()
            do {
                try await Task.sleep(for: .seconds(50))
            } catch {
                outcome.fire(Task.isCancelled)
                throw error
            }
            return HttpResponse()
        }
        let server = HttpServer(binding: .loopback(port: 0), router: router)
        try await server.start()
        let port = try #require(await server.port)
        let request = Task { try await sendRequest("GET", port: port, target: "/hold") }
        try await started.wait()
        await server.stop()
        #expect(try await outcome.wait())
        request.cancel()
        _ = await request.result
    }
}
