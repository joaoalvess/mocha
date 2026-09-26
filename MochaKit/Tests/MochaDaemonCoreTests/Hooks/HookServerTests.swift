import Foundation
import Synchronization
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct HookServerTests {
    static let secret = "test-secret"
    static let pane = "w1C:p2"

    static func headers(secret: String? = HookServerTests.secret, pane: String? = HookServerTests.pane) -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        headers["X-Mocha-Hook-Secret"] = secret
        headers["X-Mocha-Pane"] = pane
        return headers
    }

    static func withHookServer(
        secrets: HookSecretVerifier = HookSecretVerifier(secret: HookServerTests.secret),
        resolveAgent: @escaping HookServer.AgentResolver = { $0 },
        _ body: (UInt16, AsyncStream<ReceivedHook>.Iterator) async throws -> Void
    ) async throws {
        let hub = HookEventHub()
        let server = HookServer(
            secrets: secrets,
            events: hub,
            resolveAgent: resolveAgent,
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        )
        let events = hub.events()
        try await withRunningServer(server.makeRouter()) { port in
            try await body(port, events.makeAsyncIterator())
        }
    }

    static func post(_ event: HookEventName, _ file: String, port: UInt16, headers: [String: String] = headers()) async throws -> TestHttpResponse {
        try await sendRequest("POST", port: port, target: event.path, headers: headers, body: Fixtures.data("hooks/\(file)"))
    }

    static func fixtureHeaders(_ file: String) throws -> [String: String] {
        try #require(try JSONSerialization.jsonObject(with: Fixtures.data("hooks/\(file)")) as? [String: String])
    }

    @Test func everyRequestFixtureIsAnsweredWithAnEmptyObjectAndPublished() async throws {
        let requests = try HookFixtures.requests()
        try await Self.withHookServer { port, iterator in
            var iterator = iterator
            for request in requests {
                let response = try await Self.post(request.name, request.file, port: port)
                #expect(response.status == 200, "\(request.file)")
                #expect(response.header("Content-Type") == "application/json", "\(request.file)")
                #expect(String(decoding: response.body, as: UTF8.self) == "{}", "\(request.file)")
                let expected = try HookEvent.decode(request.name, from: Fixtures.data("hooks/\(request.file)"))
                let received = try #require(await iterator.next())
                #expect(received.agentId == Self.pane)
                #expect(received.receivedAt == Date(timeIntervalSince1970: 1_790_000_000))
                #expect(received.event == expected, "\(request.file)")
            }
        }
    }

    @Test func permissionRequestOfTwoMegabytesIsAcceptedAndAbove16MiBIs413() async throws {
        #expect(HookServer.maxBodySize == 16 * 1024 * 1024)
        let content = String(repeating: "a", count: 2 * 1024 * 1024)
        let body = Data(
            #"{"session_id":"33333333-3333-4333-8333-333333333333","cwd":"/Users/dev/projects/demo-app","hook_event_name":"PermissionRequest","tool_name":"Write","tool_input":{"file_path":"/Users/dev/projects/demo-app/grande.txt","content":"\#(content)"}}"#.utf8
        )
        try await Self.withHookServer { port, iterator in
            var iterator = iterator
            let accepted = try await sendRequest("POST", port: port, target: HookEventName.permissionRequest.path, headers: Self.headers(), body: body)
            #expect(accepted.status == 200)
            #expect(String(decoding: accepted.body, as: UTF8.self) == "{}")
            let received = try #require(await iterator.next())
            guard case .permissionRequest(let request) = received.event else {
                Issue.record("unexpected \(received.event.name)")
                return
            }
            #expect(request.toolInput["content"]?.stringValue?.utf8.count == content.utf8.count)

            let tooLarge = try await sendRequest(
                "POST",
                port: port,
                target: HookEventName.permissionRequest.path,
                headers: Self.headers(),
                body: Data(count: HookServer.maxBodySize + 1)
            )
            #expect(tooLarge.status == 413)
            let stop = try await Self.post(.stop, "Stop.json", port: port)
            #expect(stop.status == 200)
            #expect(try #require(await iterator.next()).event.name == .stop)
        }
    }

    @Test func withoutTheRightSecretTheAnswerIs401AndNothingIsPublished() async throws {
        try await Self.withHookServer { port, iterator in
            var iterator = iterator
            for secret in [nil, "", "outro-segredo", "test-secre"] {
                let response = try await Self.post(.stop, "Stop.json", port: port, headers: Self.headers(secret: secret))
                #expect(response.status == 401, "\(secret ?? "sem header")")
                #expect(response.body.isEmpty)
            }
            let accepted = try await Self.post(.userPromptSubmit, "UserPromptSubmit.json", port: port)
            #expect(accepted.status == 200)
            #expect(try #require(await iterator.next()).event.name == .userPromptSubmit)
        }
    }

    @Test func aDifferentSecretMakesTheServerRereadTheConfig() async throws {
        try await withTemporaryHome { home in
            try home.write(#"{"hookSecret": "segredo-novo"}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let configFile = home.paths.configFile
            let reads = ReloadCounter()
            let secrets = HookSecretVerifier(secret: "segredo-antigo") {
                reads.increment()
                return (try? DaemonConfigStore(url: configFile).read())?.hookSecret
            }
            try await Self.withHookServer(secrets: secrets) { port, iterator in
                var iterator = iterator
                let renewed = try await Self.post(.stop, "Stop.json", port: port, headers: Self.headers(secret: "segredo-novo"))
                #expect(renewed.status == 200)
                #expect(try #require(await iterator.next()).event.name == .stop)
                #expect(reads.value == 1)
                let again = try await Self.post(.stop, "Stop.json", port: port, headers: Self.headers(secret: "segredo-novo"))
                #expect(again.status == 200)
                #expect(reads.value == 1)
                let old = try await Self.post(.stop, "Stop.json", port: port, headers: Self.headers(secret: "segredo-antigo"))
                #expect(old.status == 401)
            }
        }
    }

    @Test func hookOutsideHerdrIsAnsweredAndIgnored() async throws {
        try await Self.withHookServer { port, iterator in
            var iterator = iterator
            for pane in [nil, "", "  "] {
                let response = try await Self.post(.stop, "Stop.json", port: port, headers: Self.headers(pane: pane))
                #expect(response.status == 200)
                #expect(String(decoding: response.body, as: UTF8.self) == "{}")
            }
            _ = try await Self.post(.notification, "Notification.idle_prompt.json", port: port)
            #expect(try #require(await iterator.next()).event.name == .notification)
        }
    }

    @Test func invalidPayloadIs400() async throws {
        try await Self.withHookServer { port, _ in
            let broken = try await sendRequest("POST", port: port, target: "/hooks/Stop", headers: Self.headers(), body: Data("{\"session_id\":".utf8))
            #expect(broken.status == 400)
            let missing = try await sendRequest("POST", port: port, target: "/hooks/Stop", headers: Self.headers(), body: Data("{}".utf8))
            #expect(missing.status == 400)
        }
    }

    @Test func keepAliveClientGetsConnectionCloseAndTheNextHookWorks() async throws {
        let body = try Fixtures.data("hooks/PermissionRequest.bash.json")
        var fields = try Self.fixtureHeaders("headers.http.json")
        fields["Content-Length"] = String(body.count)
        try await Self.withHookServer { port, iterator in
            var iterator = iterator
            for _ in 0..<2 {
                let client = try await RawClient.connect(to: loopbackEndpoint(port))
                defer { client.cancel() }
                let head = "POST /hooks/PermissionRequest HTTP/1.1\r\n" + fields.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
                try await client.send(Array(head.utf8) + Array(body))
                let response = String(decoding: try await client.readToEnd(), as: UTF8.self)
                #expect(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
                #expect(response.contains("\r\nConnection: close\r\n"))
                #expect(response.hasSuffix("\r\n\r\n{}"))
                #expect(await client.receivedError == nil)
                #expect(try #require(await iterator.next()).event.name == .permissionRequest)
            }

            let session = makeTestSession()
            defer { session.invalidateAndCancel() }
            for file in ["PermissionRequest.write.json", "PermissionRequest.AskUserQuestion.single.json"] {
                var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/hooks/PermissionRequest")))
                request.httpMethod = "POST"
                request.httpBody = try Fixtures.data("hooks/\(file)")
                request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                for (name, value) in Self.headers() {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                let (data, response) = try await session.data(for: request)
                #expect((response as? HTTPURLResponse)?.statusCode == 200, "\(file)")
                #expect(String(decoding: data, as: UTF8.self) == "{}")
                #expect(try #require(await iterator.next()).event.name == .permissionRequest)
            }
        }
    }

    @Test func permissionRequestIsAnsweredWithoutDecidingEvenWithAStalledConsumer() async throws {
        let hub = HookEventHub()
        let stalled = hub.events()
        let server = HookServer(secrets: HookSecretVerifier(secret: Self.secret), events: hub)
        var headers = HttpHeaders()
        for (name, value) in try Self.fixtureHeaders("headers.http.json") {
            headers.add(name, value)
        }
        let request = HttpRequest(
            method: .post,
            path: HookEventName.permissionRequest.path,
            headers: headers,
            body: try Fixtures.data("hooks/PermissionRequest.AskUserQuestion.multi.json")
        )
        let empty = try OrderedJSON.parse(Fixtures.data("hooks/response.empty.json"))

        for _ in 0...HookEventHub.subscriberBufferSize {
            let response = await server.respond(to: request, as: .permissionRequest)
            #expect(response.status == .ok)
            #expect(response.headers["Content-Type"] == "application/json")
            #expect(try OrderedJSON.parse(response.body) == empty)
        }
        #expect(hub.subscriberCount == 1)
        withExtendedLifetime(stalled) {}
    }

    @Test func movedPaneIsTranslatedBeforePublishing() async throws {
        try await Self.withHookServer(resolveAgent: { $0 == "w1C:p2" ? "w9Z:p4" : $0 }) { port, iterator in
            var iterator = iterator
            _ = try await Self.post(.sessionStart, "SessionStart.compact.json", port: port)
            let received = try #require(await iterator.next())
            #expect(received.agentId == "w9Z:p4")
            guard case .sessionStart(let hook) = received.event else {
                Issue.record("esperava SessionStart")
                return
            }
            #expect(hook.source == .compact)
        }
    }

    @Test func onlyThePostRoutesOfTheMochaEventsExist() async throws {
        try await Self.withHookServer { port, _ in
            let sessionEnd = try await sendRequest("POST", port: port, target: "/hooks/SessionEnd", headers: Self.headers(), body: Fixtures.data("hooks/SessionEnd.clear.json"))
            #expect(sessionEnd.status == 404)
            let get = try await sendRequest("GET", port: port, target: "/hooks/Stop")
            #expect(get.status == 405)
            #expect(get.header("Allow") == "POST")
        }
    }
}

final class ReloadCounter: Sendable {
    private let count = Mutex(0)

    func increment() {
        count.withLock { $0 += 1 }
    }

    var value: Int {
        count.withLock { $0 }
    }
}
