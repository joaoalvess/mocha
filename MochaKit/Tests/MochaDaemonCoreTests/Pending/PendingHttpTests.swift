import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PendingHttpTests {
    static let deviceToken = "token-do-iphone"

    static func respondBody(_ requestId: RequestID, _ response: PendingResponse) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
        object = ["requestId": requestId, "response": object]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func post(_ body: Data, port: UInt16, token: String? = deviceToken) async throws -> TestHttpResponse {
        var headers = ["Content-Type": "application/json"]
        headers["Authorization"] = token.map { "Bearer \($0)" }
        return try await sendRequest("POST", port: port, target: Gateway.respondPath, headers: headers, body: body)
    }

    static func rawHook(_ file: String, port: UInt16, secret: String = PendingSample.secret, pane: String = PendingSample.agent) async throws -> RawClient {
        let body = try PendingSample.fixture(file)
        let head = "POST /hooks/PermissionRequest HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(port)\r\n"
            + "Content-Type: application/json\r\n"
            + "Connection: keep-alive\r\n"
            + "X-Mocha-Pane: \(pane)\r\n"
            + "X-Mocha-Hook-Secret: \(secret)\r\n"
            + "Content-Length: \(body.count)\r\n\r\n"
        let client = try await RawClient.connect(to: loopbackEndpoint(port))
        try await client.send(Array(head.utf8) + Array(body))
        return client
    }

    static func body(of response: [UInt8]) -> Data {
        let text = Data(response)
        guard let range = text.range(of: Data("\r\n\r\n".utf8)) else { return Data() }
        return text[range.upperBound...]
    }

    @Test func respondRouteAuthenticatesDecodesAndAnswersTheHeldHook() async throws {
        try await withPendingHub { hub, pending in
            _ = try await hub.devices.register(name: "iPhone", token: Self.deviceToken, at: Sample.start)
            try await withRunningServer(Gateway(herdr: hub.herdr, hub: hub.hub).makeRouter()) { port in
                let question = try await pending.hold("PermissionRequest.AskUserQuestion.single.json")
                let answer = try Self.respondBody(question.requestId, .answers(["Qual banco?": ["SQLite"]]))

                #expect(try await Self.post(answer, port: port, token: nil).status == 401)
                #expect(try await Self.post(answer, port: port, token: "outro").status == 401)
                #expect(try await Self.post(Data(#"{"requestId":"x"}"#.utf8), port: port).status == 400)
                #expect(try await Self.post(try Self.respondBody(question.requestId, .allow), port: port).status == 400)
                #expect(try await Self.post(try Self.respondBody(question.requestId, .answers([:])), port: port).status == 400)
                #expect(await pending.store.contains(question.requestId))

                let accepted = try await Self.post(answer, port: port)
                #expect(accepted.status == 200)
                #expect(accepted.header("Content-Type") == "application/json")
                #expect(String(decoding: accepted.body, as: UTF8.self) == "{}")
                let reply = await question.response()
                #expect(reply.body == PendingSample.withoutTrailingNewline(try PendingSample.fixture("response.PermissionRequest.AskUserQuestion.single.json")))

                #expect(try await Self.post(answer, port: port).status == 404)
                #expect(try await Self.post(try Self.respondBody("nao-existe", .deny(reason: nil)), port: port).status == 404)
            }
        }
    }

    @Test func theHookConnectionStaysOpenUntilThePhoneAnswers() async throws {
        try await withPendingStore { harness in
            try await withRunningServer(harness.server.makeRouter()) { port in
                let client = try await Self.rawHook("PermissionRequest.bash.json", port: port)
                defer { client.cancel() }
                let requestId = try await eventually { await harness.store.requests.first?.id }

                try await harness.store.respond(to: requestId, with: .deny(reason: "Negado pelo celular: não crie arquivos agora"))

                let response = try await client.readToEnd()
                #expect(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 200 OK\r\n"))
                #expect(String(decoding: response, as: UTF8.self).contains("\r\nConnection: close\r\n"))
                #expect(Self.body(of: response) == PendingSample.withoutTrailingNewline(try PendingSample.fixture("response.PermissionRequest.deny.json")))
            }
        }
    }

    @Test func claudeClosingTheHookConnectionEndsTheRequest() async throws {
        try await withPendingStore { harness in
            try await withRunningServer(harness.server.makeRouter()) { port in
                let client = try await Self.rawHook("PermissionRequest.AskUserQuestion.single.json", port: port)
                let requestId = try await eventually { await harness.store.requests.first?.id }

                client.cancel()

                #expect(try await harness.resolution(of: requestId).reason == .connectionClosed)
                #expect(await harness.store.requests.isEmpty)
                await #expect(throws: PendingRespondError.requestNotFound) {
                    try await harness.store.respond(to: requestId, with: .deny(reason: nil))
                }
            }
        }
    }

    @Test func theDaemonHoldsThePermissionRequestAndTheRespondRouteDecidesIt() async throws {
        try await withTemporaryHome(short: true) { home in
            let port = try await DaemonRuntimeTests.freePort()
            try home.write(#"{"gatewayPort": \#(port), "hookSecret": "\#(PendingSample.secret)"}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            _ = try await DeviceStore(fileURL: home.paths.devicesFile).register(name: "iPhone", token: Self.deviceToken, at: Date())
            let runtime = DaemonRuntime(options: DaemonRuntimeTests.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath()))
            var hooks = runtime.hookEvents.events().makeAsyncIterator()
            let started = try await runtime.start()

            let client = try await Self.rawHook("PermissionRequest.bash.json", port: started.hookPort, pane: "w1C:p2")
            defer { client.cancel() }
            let requestId = try #require(await hooks.next()?.requestId)

            let accepted = try await Self.post(try Self.respondBody(requestId, .allow), port: port)
            #expect(accepted.status == 200)
            let response = try await client.readToEnd()
            #expect(Self.body(of: response) == PendingSample.withoutTrailingNewline(try PendingSample.fixture("response.PermissionRequest.allow.json")))
            #expect(try await Self.post(try Self.respondBody(requestId, .allow), port: port).status == 404)

            await runtime.stop()
        }
    }
}
