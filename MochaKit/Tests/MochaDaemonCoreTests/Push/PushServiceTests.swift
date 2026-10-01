import CryptoKit
import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PushServiceTests {
    @Test func turnDoneAlertCarriesTheSpecHeadersPayloadAndAVerifiableToken() async throws {
        let message = "**Pronto**: todos os `testes` passaram.\n\n- 12 arquivos\n- " + String(repeating: "longo ", count: 60)
        try await withPush { harness in
            try await harness.device()

            await harness.deliver(PushHooks.stop(message))

            let request = try #require(harness.transport.requests.first)
            #expect(harness.transport.requests.count == 1)
            #expect(request.url?.absoluteString == "https://api.sandbox.push.apple.com/3/device/\(PushTestData.deviceToken)")
            #expect(request.value(forHTTPHeaderField: "apns-push-type") == "alert")
            #expect(request.value(forHTTPHeaderField: "apns-topic") == "com.example.mocha")
            #expect(request.value(forHTTPHeaderField: "apns-priority") == "10")
            #expect(request.value(forHTTPHeaderField: "apns-collapse-id") == "w1:p1")
            #expect(request.value(forHTTPHeaderField: "apns-expiration") == String(Int(Sample.start.timeIntervalSince1970) + 3600))
            let apnsId = try #require(request.value(forHTTPHeaderField: "apns-id"))
            #expect(UUID(uuidString: apnsId) != nil)
            #expect(apnsId == apnsId.lowercased())

            let authorization = try #require(request.value(forHTTPHeaderField: "authorization"))
            let parts = authorization.dropFirst("bearer ".count).split(separator: ".").map(String.init)
            #expect(parts.count == 3)
            let signature = try P256.Signing.ECDSASignature(rawRepresentation: try #require(Base64URL.decode(parts[2])))
            #expect(harness.privateKey.publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)))
            let claims = try JSONDecoder().decode(ApnsJWT.Claims.self, from: try #require(Base64URL.decode(parts[1])))
            #expect(claims == ApnsJWT.Claims(iss: PushTestData.teamId, iat: Int(Sample.start.timeIntervalSince1970)))

            let payload = try #require(try harness.payloads().first)
            let aps = try #require(payload["aps"] as? [String: Any])
            let alert = try #require(aps["alert"] as? [String: Any])
            let body = try #require(alert["body"] as? String)
            #expect(alert["title"] as? String == "Claude terminou · Core")
            #expect(body == PlainText.preview(fromMarkdown: message, limit: 180))
            #expect(body.count <= 180 && body.count > 170)
            #expect(body.hasPrefix("Pronto: todos os testes passaram."))
            #expect(aps["sound"] as? String == "default")
            #expect(aps["thread-id"] as? String == "w1:p1")
            #expect(aps["category"] as? String == "TURN_DONE")
            #expect(aps["interruption-level"] == nil)
            #expect(payload["agentId"] as? String == "w1:p1")
            #expect(payload["kind"] as? String == "turnDone")
            #expect(payload["requestId"] == nil)
            #expect((payload["sentAt"] as? NSNumber)?.int64Value == Int64(Sample.start.timeIntervalSince1970 * 1000))
            #expect(await harness.service.configurationIssues().isEmpty)
        }
    }

    @Test func permissionRequestAlertsAtOnceWithTheRequestSummary() async throws {
        try await withPush { harness in
            try await harness.device(env: .production)

            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.AskUserQuestion.single.json"))

            let requests = harness.transport.requests
            #expect(requests.count == 2)
            #expect(requests.allSatisfy { $0.url?.host() == "api.push.apple.com" })
            #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "apns-expiration") == String(Int(Sample.start.timeIntervalSince1970) + 600) })
            let payloads = try harness.payloads()
            let alerts = payloads.compactMap { ($0["aps"] as? [String: Any])?["alert"] as? [String: Any] }
            #expect(alerts.map { $0["title"] as? String } == ["Claude precisa de você · Core", "Claude precisa de você · Core"])
            #expect(alerts.map { $0["body"] as? String } == ["touch f.txt", "Qual banco?"])
            for payload in payloads {
                let aps = try #require(payload["aps"] as? [String: Any])
                #expect(aps["category"] as? String == "NEEDS_INPUT")
                #expect(aps["interruption-level"] as? String == "time-sensitive")
                #expect(payload["kind"] as? String == "needsInput")
            }
        }
    }

    @Test func aDeviceWithTheAgentInTheForegroundGetsNoAlert() async throws {
        try await withPush { harness in
            let watching = try await harness.device("iPhone")
            try await harness.device("iPad", token: PushHarness.otherToken)
            harness.audience.setForeground([watching.id], for: "w1:p1")

            await harness.deliver(PushHooks.stop())
            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            #expect(harness.transport.requests.compactMap { $0.url?.lastPathComponent } == [PushHarness.otherToken, PushHarness.otherToken])

            await harness.deliver(PushHooks.stop(), agent: "w9:p9")
            let others = harness.transport.requests.dropFirst(2).compactMap { $0.url?.lastPathComponent }
            #expect(Set(others) == [PushTestData.deviceToken, PushHarness.otherToken])
        }
    }

    @Test func aDeviceWithTheLiveActivityCardGetsNoAlertOfAnyAgent() async throws {
        try await withPush { harness in
            let covered = try await harness.device("iPhone")
            try await harness.device("iPad", token: PushHarness.otherToken)
            let cards = FakeCardHolder()
            await harness.service.attachLiveActivity(cards)
            #expect(await cards.handoff != nil)
            await cards.cover([covered.id])

            await harness.deliver(PushHooks.stop())
            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            await harness.deliver(PushHooks.stop(), agent: "w9:p9")
            #expect(harness.transport.requests.compactMap { $0.url?.lastPathComponent } == Array(repeating: PushHarness.otherToken, count: 3))

            await cards.cover([])
            await harness.deliver(PushHooks.stop())
            #expect(harness.transport.requests.compactMap { $0.url?.lastPathComponent }.suffix(2).sorted() == [PushHarness.otherToken, PushTestData.deviceToken].sorted())
        }
    }

    @Test func aLostCardHandsItsAlertsToNotificationsWithTheCardText() async throws {
        try await withPush { harness in
            let phone = try await harness.device("iPhone")
            let lost = [
                LiveActivityLostAlert(agentId: "w1:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · demo-app", body: "parser pronto"),
                LiveActivityLostAlert(agentId: "w2:p1", kind: .needsInput, requestId: "req-a", title: "Claude precisa de você · demo-app", body: "rm -rf build"),
                LiveActivityLostAlert(agentId: "w3:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · api", body: "testes prontos"),
            ]
            harness.audience.setForeground([phone.id], for: "w3:p1")

            await harness.service.cardLost(lost, on: phone.id)
            await harness.service.waitForDeliveries()

            let payloads = try harness.payloads()
            #expect(payloads.map { $0["agentId"] as? String } == ["w1:p1", "w2:p1"])
            let alerts = payloads.compactMap { ($0["aps"] as? [String: Any]).flatMap { $0["alert"] as? [String: Any] } }
            #expect(alerts.map { $0["title"] as? String } == ["Claude terminou · demo-app", "Claude precisa de você · demo-app"])
            #expect(alerts.map { $0["body"] as? String } == ["parser pronto", "rm -rf build"])
            #expect(payloads.map { ($0["aps"] as? [String: Any])?["category"] as? String } == [PushAlertKind.turnDone.category, PushAlertKind.needsInput.category])
            #expect(payloads.map { $0["requestId"] as? String } == [nil, "req-a"])
            #expect(harness.transport.requests.allSatisfy { $0.url?.lastPathComponent == PushTestData.deviceToken })
        }
    }

    @Test func aHookRightAfterALostCardDoesNotRingTheSameAlertAgain() async throws {
        try await withPush { harness in
            let phone = try await harness.device("iPhone")
            let lost = LiveActivityLostAlert(agentId: "w1:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · Core", body: "pronto")

            await harness.service.cardLost([lost], on: phone.id)
            await harness.service.waitForDeliveries()
            await harness.deliver(PushHooks.stop())
            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            #expect(try harness.payloads().map { $0["kind"] as? String } == ["turnDone", "needsInput"])

            harness.clock.advance(by: .seconds(10))
            await harness.deliver(PushHooks.stop())
            #expect(try harness.payloads().map { $0["kind"] as? String } == ["turnDone", "needsInput", "turnDone"])
        }
    }

    @Test func aLostCardRespectsTheTurnDonePreference() async throws {
        try await withPush { harness in
            let phone = try await harness.device("iPhone", turnDoneAlerts: false)
            let lost = [
                LiveActivityLostAlert(agentId: "w1:p1", kind: .turnDone, requestId: nil, title: "Claude terminou · demo-app", body: "parser pronto"),
                LiveActivityLostAlert(agentId: "w2:p1", kind: .needsInput, requestId: nil, title: "Claude precisa de você · demo-app", body: "Responda no Mac."),
            ]

            await harness.service.cardLost(lost, on: phone.id)
            await harness.service.cardLost(lost, on: "sumiu")
            await harness.service.waitForDeliveries()

            #expect(try harness.payloads().map { $0["kind"] as? String } == ["needsInput"])
        }
    }

    @Test func aTurnDoneWaitsForTheCooldownAndIsDroppedWhenTheAgentWorksAgain() async throws {
        let audience = FakePushAudience(agents: [Sample.agent("w1:p1", sessionId: Sample.sessionA), Sample.agent("w2:p1")])
        try await withPush(audience: audience, configuration: PushServiceConfiguration()) { harness in
            try await harness.device()

            await harness.deliver(PushHooks.stop("parser pronto"))
            await harness.deliver(PushHooks.stop("testes prontos"), agent: "w2:p1")
            #expect(harness.transport.requests.isEmpty)
            #expect(await harness.service.pendingTurnDoneChecks == 2)

            try await harness.clock.waitForSleepers(2)
            harness.audience.setAgent(Sample.agent("w2:p1", status: .working))
            harness.clock.advance(by: .seconds(5))
            try await harness.settleTurnDoneChecks()

            let payloads = try harness.payloads()
            #expect(payloads.map { $0["agentId"] as? String } == ["w1:p1"])
            #expect((payloads.first?["sentAt"] as? NSNumber)?.int64Value == Int64(Sample.start.addingTimeInterval(5).timeIntervalSince1970 * 1000))
        }
    }

    @Test func aSecondStopRestartsTheTurnDoneCooldown() async throws {
        try await withPush(configuration: PushServiceConfiguration()) { harness in
            try await harness.device()

            await harness.deliver(PushHooks.stop("primeiro"))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(3))
            await harness.deliver(PushHooks.stop("segundo"))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(3))
            await harness.service.waitForDeliveries()
            #expect(harness.transport.requests.isEmpty)

            harness.clock.advance(by: .seconds(2))
            try await harness.settleTurnDoneChecks()
            let alerts = try harness.payloads().compactMap { ($0["aps"] as? [String: Any]).flatMap { $0["alert"] as? [String: Any] } }
            #expect(alerts.map { $0["body"] as? String } == ["segundo"])
        }
    }

    @Test func twoTurnsDoneAtOnceRingOnTheCardOneAfterTheOther() async throws {
        try await withPush { harness in
            let covered = try await harness.device("iPhone")
            let cardSender = FakeLiveActivitySender()
            let cards = LiveActivityService(
                devices: harness.devices,
                sender: cardSender,
                clock: harness.clock,
                configuration: LiveActivityConfiguration(updateInterval: 0, turnDoneCooldown: 0, blockedGrace: 0, blockedAlertWindow: 0)
            )
            await harness.service.attachLiveActivity(cards)
            try await cards.register(
                LiveActivityRegistration(activityId: "act-1", updateToken: String(repeating: "b2", count: 40), env: .sandbox),
                from: covered.id
            )
            await cards.apply(LiveActivityInput(agents: [LiveActivitySample.agent("w1:p1", .working), LiveActivitySample.agent("w2:p1", .working)]))
            await cards.waitForSends()

            await harness.deliver(PushHooks.stop("parser pronto"))
            await harness.deliver(PushHooks.stop("testes prontos"), agent: "w2:p1")
            #expect(harness.transport.requests.isEmpty)
            await cards.apply(LiveActivityInput(agents: [LiveActivitySample.agent("w1:p1", .idle), LiveActivitySample.agent("w2:p1", .idle)]))
            await cards.waitForSends()
            await harness.service.waitForDeliveries()

            let alerts = cardSender.sent.suffix(2).map { ($0.push.agentId, $0.push.event) }
            #expect(alerts.map(\.0) == ["w1:p1", "w2:p1"])
            #expect(alerts.map(\.1) == [
                .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Turno concluído.")),
                .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Turno concluído.")),
            ])
            #expect(harness.transport.requests.isEmpty)
            await cards.shutdown()
        }
    }

    @Test func theLiveActivityServiceTellsWhichDevicesHaveACardWithAnUpdateToken() async throws {
        try await withPush { harness in
            let covered = try await harness.device("iPhone")
            let starter = try await harness.device("iPad", token: PushHarness.otherToken)
            let cards = LiveActivityService(devices: harness.devices, sender: FakeLiveActivitySender(), clock: harness.clock)
            await harness.service.attachLiveActivity(cards)
            try await cards.register(
                LiveActivityRegistration(activityId: "act-1", updateToken: String(repeating: "b2", count: 40), env: .sandbox),
                from: covered.id
            )
            try await cards.register(LiveActivityRegistration(pushToStartToken: String(repeating: "a1", count: 40), env: .sandbox), from: starter.id)
            #expect(await cards.cardDevices() == [covered.id])

            await harness.deliver(PushHooks.stop())
            await harness.deliver(PushHooks.stop(), agent: "w2:p1")
            #expect(harness.transport.requests.compactMap { $0.url?.lastPathComponent } == [PushHarness.otherToken, PushHarness.otherToken])
            await cards.shutdown()
        }
    }

    @Test func turnDoneRespectsThePreferenceButNeedsInputAlwaysGoes() async throws {
        try await withPush { harness in
            try await harness.device(turnDoneAlerts: false)

            await harness.deliver(PushHooks.stop())
            #expect(harness.transport.requests.isEmpty)
            #expect(harness.loads.value == 0)

            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            #expect(harness.transport.requests.count == 1)
        }
    }

    @Test func secondarySignalsWithinTenSecondsOfARequestAreDeduplicated() async throws {
        try await withPush { harness in
            try await harness.device()

            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            #expect(harness.transport.requests.count == 1)

            harness.clock.advance(by: .seconds(6))
            await harness.deliver(PushHooks.notification())
            await harness.service.agentStatusChanged("w1:p1", to: .blocked)
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()
            #expect(harness.transport.requests.count == 1)

            harness.clock.advance(by: .seconds(3))
            await harness.deliver(PushHooks.notification())
            #expect(harness.transport.requests.count == 2)
            let alert = try #require((try harness.payloads().last?["aps"] as? [String: Any])?["alert"] as? [String: Any])
            #expect(alert["body"] as? String == "Esperando uma resposta no terminal.")

            await harness.deliver(PushHooks.notification())
            await harness.deliver(PushHooks.notification(.idlePrompt))
            #expect(harness.transport.requests.count == 2)
        }
    }

    @Test func blockedWithoutARequestAlertsAfterTheGraceOnlyForClaude() async throws {
        let audience = FakePushAudience(agents: [
            Sample.agent("w1:p1", sessionId: Sample.sessionA),
            Sample.agent("w1:p2", kind: "codex", title: "codex"),
        ])
        try await withPush(audience: audience) { harness in
            try await harness.device()

            await harness.service.agentStatusChanged("w1:p2", to: .blocked)
            await harness.service.agentStatusChanged("w1:p1", to: .blocked)
            await harness.service.agentStatusChanged("w1:p1", to: .blocked)
            try await harness.clock.waitForSleepers(2)
            #expect(harness.clock.pendingDelays == [.seconds(1), .seconds(1)])
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()

            #expect(harness.transport.requests.count == 1)
            let payload = try #require(try harness.payloads().first)
            #expect(payload["agentId"] as? String == "w1:p1")
            #expect(payload["kind"] as? String == "needsInput")
            let alert = try #require((payload["aps"] as? [String: Any])?["alert"] as? [String: Any])
            #expect(alert["title"] as? String == "Claude precisa de você · Core")
            #expect(alert["body"] as? String == "Esperando uma resposta no terminal.")

            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))
            #expect(harness.transport.requests.count == 2)
        }
    }

    @Test func blockedThatClearsWithinTheGraceDoesNotAlert() async throws {
        try await withPush { harness in
            try await harness.device()

            await harness.service.agentStatusChanged("w1:p1", to: .blocked)
            try await harness.clock.waitForSleepers(1)
            await harness.service.agentStatusChanged("w1:p1", to: .working)
            harness.clock.advance(by: .seconds(1))
            try await harness.settleBlockedChecks()

            #expect(harness.transport.requests.isEmpty)
        }
    }

    @Test(arguments: [
        ApnsResponse(status: 410, reason: "Unregistered"),
        ApnsResponse(status: 400, reason: "BadDeviceToken"),
    ])
    func invalidTokenIsRemovedFromTheDeviceWithoutRetry(_ response: ApnsResponse) async throws {
        try await withPush(responses: [response]) { harness in
            let record = try await harness.device()

            await harness.deliver(PushHooks.stop())

            #expect(harness.transport.requests.count == 1)
            let stored = try await harness.devices.devices()
            #expect(stored.map(\.id) == [record.id])
            #expect(stored.first?.apns == nil)
            #expect(harness.clock.sleeperCount == 0)
            #expect(await harness.service.configurationIssues().isEmpty)
        }
    }

    @Test(arguments: ["BadEnvironmentKeyInToken", "BadEnvironmentKeyIdInToken", "InvalidProviderToken", "TopicDisallowed"])
    func configurationErrorIsNotRetriedAndShowsInTheDoctor(_ reason: String) async throws {
        try await withPush(responses: [ApnsResponse(status: 403, reason: reason)]) { harness in
            try await harness.device(env: .production)

            await harness.deliver(PushHooks.stop())

            #expect(harness.transport.requests.count == 1)
            #expect(harness.clock.sleeperCount == 0)
            #expect(try await harness.devices.devices().first?.apns != nil)
            let issues = await harness.service.configurationIssues()
            #expect(issues == [ApnsConfigurationIssue(environment: .production, status: 403, reason: reason, at: Sample.start)])

            let item = DoctorChecks.apns(
                config: .success(ApnsConfig(teamId: PushTestData.teamId, keyId: PushTestData.keyId, bundleId: PushTestData.bundleId)),
                signature: .teamSigned,
                binary: "~/.local/bin/mochad",
                keychain: { _ in .present },
                issues: issues
            )
            #expect(item.status == .failure)
            #expect(item.summary == "com pendências")
            #expect(item.details.contains { $0.contains("o APNs production recusou o último envio com 403 \(reason)") })

            await harness.deliver(PushHooks.stop())
            #expect(harness.transport.requests.count == 2)
            #expect(harness.loads.value == 2)
            #expect(await harness.service.configurationIssues().isEmpty)
        }
    }

    @Test func expiredProviderTokenIsRenewedAndRetriedOnce() async throws {
        try await withPush(responses: [ApnsResponse(status: 403, reason: "ExpiredProviderToken")]) { harness in
            try await harness.device()

            await harness.deliver(PushHooks.stop())

            let requests = harness.transport.requests
            #expect(requests.count == 2)
            #expect(requests[0].value(forHTTPHeaderField: "authorization") != requests[1].value(forHTTPHeaderField: "authorization"))
            #expect(requests[0].value(forHTTPHeaderField: "apns-id") == requests[1].value(forHTTPHeaderField: "apns-id"))
            #expect(await harness.service.configurationIssues().isEmpty)
            #expect(harness.loads.value == 1)
        }
    }

    @Test func tooManyRequestsAndServerErrorsBackOff() async throws {
        let responses = [ApnsResponse(status: 429, reason: "TooManyRequests"), ApnsResponse(status: 503, reason: "ServiceUnavailable")]
        try await withPush(responses: responses) { harness in
            try await harness.device()

            await harness.service.handle(ReceivedHook(agentId: "w1:p1", receivedAt: Sample.start, event: PushHooks.stop()))
            try await harness.clock.waitForSleepers(1)
            #expect(harness.transport.requests.count == 1)
            #expect(harness.clock.pendingDelays == [.seconds(1)])
            harness.clock.advance(by: .seconds(1))
            try await harness.clock.waitForSleepers(1)
            #expect(harness.transport.requests.count == 2)
            #expect(harness.clock.pendingDelays == [.seconds(2)])
            harness.clock.advance(by: .seconds(2))
            await harness.service.waitForDeliveries()

            let requests = harness.transport.requests
            #expect(requests.count == 3)
            #expect(Set(requests.compactMap { $0.value(forHTTPHeaderField: "apns-id") }).count == 1)
        }
    }

    @Test func backoffGivesUpAfterTheLastDelay() async throws {
        let failure = ApnsResponse(status: 500, reason: "InternalServerError")
        try await withPush(responses: [failure, failure, failure], configuration: PushServiceConfiguration(retryDelays: [.seconds(1)], turnDoneCooldown: .zero)) { harness in
            try await harness.device()

            await harness.service.handle(ReceivedHook(agentId: "w1:p1", receivedAt: Sample.start, event: PushHooks.stop()))
            try await harness.clock.waitForSleepers(1)
            harness.clock.advance(by: .seconds(1))
            await harness.service.waitForDeliveries()

            #expect(harness.transport.requests.count == 2)
            #expect(harness.clock.sleeperCount == 0)
        }
    }

    @Test func withoutARegisteredTokenTheKeyIsNeverLoaded() async throws {
        try await withPush { harness in
            _ = try await harness.devices.register(name: "iPhone sem push", token: "t", at: Sample.start)

            await harness.deliver(PushHooks.stop())
            await harness.deliver(try PushHooks.fixture(.permissionRequest, "PermissionRequest.bash.json"))

            #expect(harness.transport.requests.isEmpty)
            #expect(harness.loads.value == 0)
        }
    }

    @Test func missingCredentialsSkipTheAlertAndAreRetriedNextTime() async throws {
        try await withPush(credentialsError: .notConfigured) { harness in
            try await harness.device()

            await harness.deliver(PushHooks.stop())
            await harness.deliver(PushHooks.stop())

            #expect(harness.transport.requests.isEmpty)
            #expect(harness.loads.value == 2)
        }
    }

    @Test func theSameTokenOnTwoDevicesGetsOneAlert() async throws {
        try await withPush { harness in
            let registration = ApnsRegistration(token: PushTestData.deviceToken, env: .sandbox)
            let records = ["a", "b"].map { id in
                DeviceRecord(id: id, name: id, tokenSha256: id, createdAt: Sample.start, lastSeenAt: Sample.start, apns: registration)
            }
            try JSONEncoder().encode(records).write(to: harness.devices.fileURL)

            await harness.deliver(PushHooks.stop())

            #expect(harness.transport.requests.count == 1)
        }
    }
}

private actor FakeCardHolder: LiveActivityCardHolding {
    private var devices: Set<DeviceID> = []
    private(set) var handoff: (any LiveActivityAlertHandoff)?

    func attachAlertHandoff(_ handoff: any LiveActivityAlertHandoff) {
        self.handoff = handoff
    }

    func cardDevices() -> Set<DeviceID> {
        devices
    }

    func cover(_ devices: Set<DeviceID>) {
        self.devices = devices
    }
}
