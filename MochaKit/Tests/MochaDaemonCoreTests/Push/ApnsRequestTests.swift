import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

struct ApnsRequestTests {
    private let apnsId = UUID(uuidString: "123E4567-E89B-12D3-A456-4266554400A0") ?? UUID()

    @Test func alertRequestBuildsPathAndHeaders() throws {
        let request = ApnsRequest(
            deviceToken: PushTestData.deviceToken.uppercased(),
            environment: .sandbox,
            pushType: .alert,
            topic: ApnsTopic.alert(bundleId: "com.example.mocha"),
            priority: .high,
            expiration: .at(Date(timeIntervalSince1970: 1_790_003_600.2)),
            collapseId: "w17:p1",
            apnsId: apnsId,
            payload: Data("{}".utf8)
        )
        let urlRequest = try request.urlRequest(authorizationToken: "jwt")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.url?.absoluteString == "https://api.sandbox.push.apple.com/3/device/" + PushTestData.deviceToken)
        #expect(urlRequest.value(forHTTPHeaderField: "authorization") == "bearer jwt")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-push-type") == "alert")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-topic") == "com.example.mocha")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-priority") == "10")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-id") == "123e4567-e89b-12d3-a456-4266554400a0")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-expiration") == "1790003601")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-collapse-id") == "w17:p1")
        #expect(urlRequest.httpBody == Data("{}".utf8))
    }

    @Test func liveActivityRequestUsesPushTypeTopicAndProduction() throws {
        let request = ApnsRequest(
            deviceToken: PushTestData.deviceToken,
            environment: .production,
            pushType: .liveactivity,
            topic: ApnsTopic.liveActivity(bundleId: "com.example.mocha"),
            priority: .low,
            expiration: .deliverOnce,
            payload: Data("{}".utf8)
        )
        let urlRequest = try request.urlRequest(authorizationToken: "jwt")
        #expect(urlRequest.url?.host() == "api.push.apple.com")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-push-type") == "liveactivity")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-topic") == "com.example.mocha.push-type.liveactivity")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-priority") == "5")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-expiration") == "0")
        #expect(urlRequest.value(forHTTPHeaderField: "apns-collapse-id") == nil)
    }

    @Test func optionalHeadersAreOmitted() throws {
        let request = ApnsRequest(
            deviceToken: PushTestData.deviceToken,
            environment: .sandbox,
            pushType: .alert,
            topic: "com.example.mocha",
            priority: .high,
            payload: Data("{}".utf8)
        )
        #expect(request.headers.map(\.name) == ["apns-push-type", "apns-topic", "apns-priority", "apns-id"])
    }

    @Test func validationRejectsBadTokenLongCollapseIdAndLargePayload() {
        func request(token: String = PushTestData.deviceToken, collapseId: String? = nil, payloadSize: Int = 2) -> ApnsRequest {
            ApnsRequest(
                deviceToken: token,
                environment: .sandbox,
                pushType: .alert,
                topic: "com.example.mocha",
                priority: .high,
                collapseId: collapseId,
                payload: Data(repeating: 0x20, count: payloadSize)
            )
        }
        #expect(throws: ApnsError.invalidDeviceToken) { try request(token: "").validate() }
        #expect(throws: ApnsError.invalidDeviceToken) { try request(token: "abc").validate() }
        #expect(throws: ApnsError.invalidDeviceToken) { try request(token: "zz").validate() }
        #expect(throws: ApnsError.collapseIdTooLong(bytes: 65)) { try request(collapseId: String(repeating: "a", count: 65)).validate() }
        #expect(throws: ApnsError.payloadTooLarge(bytes: 4097)) { try request(payloadSize: 4097).validate() }
        #expect(throws: Never.self) { try request(collapseId: String(repeating: "a", count: 64), payloadSize: 4096).validate() }
    }

    @Test func responseParsesErrorReasonAndInactiveTimestamp() {
        let headers = ["apns-id": "id-1", "apns-unique-id": "unique-1"]
        let gone = ApnsResponse(
            status: 410,
            headerValue: { headers[$0] },
            body: Data(#"{"reason":"Unregistered","timestamp":1790000000123}"#.utf8),
            networkProtocol: "h2"
        )
        #expect(gone.reason == "Unregistered")
        #expect(gone.apnsId == "id-1")
        #expect(gone.uniqueId == "unique-1")
        #expect(gone.inactiveSince == Date(timeIntervalSince1970: 1_790_000_000.123))
        #expect(gone.deviceTokenIsInvalid)
        let badToken = ApnsResponse(status: 400, headerValue: { _ in nil }, body: Data(#"{"reason":"BadDeviceToken"}"#.utf8), networkProtocol: nil)
        #expect(badToken.deviceTokenIsInvalid)
        let ok = ApnsResponse(status: 200, headerValue: { headers[$0] }, body: Data(), networkProtocol: "h2")
        #expect(ok.isSuccess)
        #expect(ok.reason == nil)
        #expect(!ok.deviceTokenIsInvalid)
    }

    @Test func clientSignsRequestAndSendsThroughTransport() async throws {
        let transport = FakeApnsTransport()
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let client = ApnsClient(tokens: ApnsTokenProvider(key: try PushTestData.signingKey(), now: { clock.now }), transport: transport)
        let request = ApnsRequest(
            deviceToken: PushTestData.deviceToken,
            environment: .sandbox,
            pushType: .alert,
            topic: "com.example.mocha",
            priority: .high,
            payload: Data("{}".utf8)
        )
        let response = try await client.send(request)
        #expect(response.isSuccess)
        let sent = try #require(transport.requests.first)
        let authorization = try #require(sent.value(forHTTPHeaderField: "authorization"))
        #expect(authorization.hasPrefix("bearer "))
        #expect(authorization.dropFirst("bearer ".count).split(separator: ".").count == 3)
    }

    @Test func clientRenewsTokenAfterExpiredProviderToken() async throws {
        let transport = FakeApnsTransport(responses: [ApnsResponse(status: 403, reason: "ExpiredProviderToken")])
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let client = ApnsClient(tokens: ApnsTokenProvider(key: try PushTestData.signingKey(), now: { clock.now }), transport: transport)
        let request = ApnsRequest(
            deviceToken: PushTestData.deviceToken,
            environment: .sandbox,
            pushType: .alert,
            topic: "com.example.mocha",
            priority: .high,
            payload: Data("{}".utf8)
        )
        #expect(try await client.send(request).reason == "ExpiredProviderToken")
        clock.advance(by: 1)
        _ = try await client.send(request)
        let tokens = transport.requests.compactMap { $0.value(forHTTPHeaderField: "authorization") }
        #expect(tokens.count == 2)
        #expect(tokens[0] != tokens[1])
    }

    @Test func clientDoesNotSendInvalidRequest() async throws {
        let transport = FakeApnsTransport()
        let client = ApnsClient(tokens: ApnsTokenProvider(key: try PushTestData.signingKey()), transport: transport)
        let request = ApnsRequest(
            deviceToken: "nope",
            environment: .sandbox,
            pushType: .alert,
            topic: "com.example.mocha",
            priority: .high,
            payload: Data("{}".utf8)
        )
        await #expect(throws: ApnsError.invalidDeviceToken) { try await client.send(request) }
        #expect(transport.requests.isEmpty)
    }
}
