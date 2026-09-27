import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct GatewayPendingResponderTests {
    private static let pairingURL = "wss://mac-mini.tail1234.ts.net/v1"
    private static let requestId = "5e3b0000-0000-4000-8000-000000000001"

    private static func responder(_ transport: FakeUploadTransport, paired: Bool = true) throws -> GatewayPendingResponder {
        let credential = paired ? DeviceCredential(url: try #require(URL(string: pairingURL)), token: "device-token-1") : nil
        return GatewayPendingResponder(tokenStore: FakeTokenStore(credential: credential), transport: transport)
    }

    @Test func postsTheResponseToTheRespondRouteWithBearer() async throws {
        let transport = FakeUploadTransport(.status(200, Data("{}".utf8)))
        let result = await (try Self.responder(transport)).respond(to: Self.requestId, with: .answers(["Qual formato?": ["JSON"]]))
        #expect(result == .accepted)
        let call = try #require(transport.calls.first)
        #expect(transport.calls.count == 1)
        #expect(call.request.url == URL(string: "https://mac-mini.tail1234.ts.net/v1/respond"))
        #expect(call.request.httpMethod == "POST")
        #expect(call.request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token-1")
        #expect(call.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(try JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        #expect(body["requestId"] as? String == Self.requestId)
        let expected = try JSONSerialization.jsonObject(with: Fixtures.data("protocol/pendingResponse.answers.json")) as? NSDictionary
        #expect(body["response"] as? NSDictionary == expected)
    }

    @Test(arguments: [
        ("protocol/pendingResponse.allow.json", PendingResponse.allow),
        ("protocol/pendingResponse.deny.noReason.json", PendingResponse.deny(reason: nil)),
    ])
    func responseBodyMatchesTheProtocolFixtures(fixture: String, response: PendingResponse) async throws {
        let transport = FakeUploadTransport(.status(200, Data("{}".utf8)))
        _ = await (try Self.responder(transport)).respond(to: Self.requestId, with: response)
        let call = try #require(transport.calls.first)
        let body = try #require(try JSONSerialization.jsonObject(with: call.body) as? [String: Any])
        let expected = try JSONSerialization.jsonObject(with: Fixtures.data(fixture)) as? NSDictionary
        #expect(body["response"] as? NSDictionary == expected)
    }

    @Test(arguments: [
        (200, PendingRespondResult.accepted),
        (404, .gone),
        (400, .refused),
        (401, .unauthorized),
        (502, .unexpectedStatus(502)),
    ])
    func statusMapsToTheResult(status: Int, result: PendingRespondResult) async throws {
        let transport = FakeUploadTransport(.status(status, Data()))
        #expect(await (try Self.responder(transport)).respond(to: Self.requestId, with: .allow) == result)
    }

    @Test func transportFailureIsUnreachable() async throws {
        #expect(await (try Self.responder(FakeUploadTransport(.failure))).respond(to: Self.requestId, with: .allow) == .unreachable)
        #expect(await (try Self.responder(FakeUploadTransport(.notHTTP))).respond(to: Self.requestId, with: .allow) == .unreachable)
    }

    @Test func withoutPairingNothingIsSent() async throws {
        let transport = FakeUploadTransport(.status(200, Data()))
        #expect(await (try Self.responder(transport, paired: false)).respond(to: Self.requestId, with: .allow) == .notPaired)
        #expect(transport.calls.isEmpty)
    }

    @Test(arguments: [
        ("wss://mac-mini.tail1234.ts.net/v1", "https://mac-mini.tail1234.ts.net/v1/respond"),
        ("ws://127.0.0.1:8787/v1", "http://127.0.0.1:8787/v1/respond"),
        ("https://mac.example/v1?x=1#y", "https://mac.example/v1/respond"),
    ])
    func respondURLFollowsThePairingHost(pairing: String, expected: String) throws {
        #expect(GatewayPendingResponder.respondURL(forPairingURL: try #require(URL(string: pairing)))?.absoluteString == expected)
    }

    @Test func unsupportedPairingSchemeHasNoURL() throws {
        #expect(GatewayPendingResponder.respondURL(forPairingURL: try #require(URL(string: "ftp://mac/v1"))) == nil)
    }
}
