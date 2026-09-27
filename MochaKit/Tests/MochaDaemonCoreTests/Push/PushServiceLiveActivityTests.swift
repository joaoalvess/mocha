import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PushServiceLiveActivityTests {
    private static let token = String(repeating: "b2", count: 40)
    private static let push = AgentActivityPush(
        agentId: "w1:p1",
        event: .update(alert: nil),
        contentState: AgentActivityContentState(
            agent: .init(agentId: "w1:p1", title: "Refatorar o parser", workspaceLabel: "demo-app", status: "working", since: Sample.start),
            pending: nil,
            updatedAt: Sample.start
        ),
        timestamp: Sample.start,
        staleDate: Sample.start.addingTimeInterval(15 * 60)
    )

    @Test(arguments: [(ApnsPriority.high, "10"), (ApnsPriority.low, "5")])
    func sendsWithTheLiveActivityHeaders(_ priority: ApnsPriority, _ header: String) async throws {
        try await withPush { harness in
            let delivery = await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: priority)
            #expect(delivery == .delivered)
            #expect(harness.transport.requests.count == 1)
            let request = try #require(harness.transport.requests.first)
            #expect(request.url?.absoluteString == "https://api.sandbox.push.apple.com/3/device/\(Self.token)")
            #expect(request.value(forHTTPHeaderField: "apns-push-type") == "liveactivity")
            #expect(request.value(forHTTPHeaderField: "apns-topic") == "com.example.mocha.push-type.liveactivity")
            #expect(request.value(forHTTPHeaderField: "apns-priority") == header)
            let apnsId = try #require(request.value(forHTTPHeaderField: "apns-id"))
            #expect(UUID(uuidString: apnsId) != nil)
            #expect(apnsId == apnsId.lowercased())
            #expect(request.value(forHTTPHeaderField: "apns-expiration") == nil)
            #expect(request.value(forHTTPHeaderField: "apns-collapse-id") == nil)
            #expect(request.value(forHTTPHeaderField: "authorization")?.hasPrefix("bearer ") == true)
            #expect(request.httpBody == (try Self.push.payload()))
        }
    }

    @Test func productionTokensGoToTheProductionHost() async throws {
        try await withPush { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token.uppercased(), environment: .production, priority: .high) == .delivered)
            #expect(harness.transport.requests.first?.url?.absoluteString == "https://api.push.apple.com/3/device/\(Self.token)")
        }
    }

    @Test(arguments: [ApnsResponse(status: 410, reason: "Unregistered"), ApnsResponse(status: 400, reason: "BadDeviceToken")])
    func refusedTokensAreReportedAsInvalid(_ response: ApnsResponse) async throws {
        try await withPush(responses: [response]) { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .invalidToken)
            #expect(harness.transport.requests.count == 1)
            #expect(await harness.service.configurationIssues().isEmpty)
        }
    }

    @Test(arguments: [429, 500, 503])
    func throttlingAndServerErrorsAreRetryable(_ status: Int) async throws {
        try await withPush(responses: [ApnsResponse(status: status, reason: "TooManyRequests")]) { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .failed(retryable: true))
            #expect(harness.transport.requests.count == 1)
        }
    }

    @Test func configurationErrorsAreRecordedAndNotRetryable() async throws {
        try await withPush(responses: [ApnsResponse(status: 403, reason: "TopicDisallowed")]) { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .failed(retryable: false))
            #expect(
                await harness.service.configurationIssues() == [
                    ApnsConfigurationIssue(environment: .sandbox, status: 403, reason: "TopicDisallowed", at: Sample.start),
                ]
            )

            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .delivered)
            #expect(harness.loads.value == 2)
            #expect(await harness.service.configurationIssues().isEmpty)
        }
    }

    @Test func anExpiredProviderTokenIsRenewedAndSentOnceMore() async throws {
        try await withPush(responses: [ApnsResponse(status: 403, reason: "ExpiredProviderToken")]) { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .delivered)
            #expect(harness.transport.requests.count == 2)
        }
    }

    @Test func missingCredentialsSendNothing() async throws {
        try await withPush(credentialsError: .keyNotFound(keyId: PushTestData.keyId)) { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .failed(retryable: false))
            #expect(harness.transport.requests.isEmpty)
        }
    }

    @Test func anInvalidTokenIsNotSent() async throws {
        try await withPush { harness in
            #expect(await harness.service.sendLiveActivity(Self.push, to: "xyz", environment: .sandbox, priority: .high) == .failed(retryable: false))
            #expect(harness.transport.requests.isEmpty)
        }
    }

    @Test func nothingIsSentAfterShutdown() async throws {
        try await withPush { harness in
            await harness.service.shutdown()
            #expect(await harness.service.sendLiveActivity(Self.push, to: Self.token, environment: .sandbox, priority: .high) == .failed(retryable: false))
            #expect(harness.transport.requests.isEmpty)
        }
    }
}
