import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityServiceTests {
    private let working = [LiveActivitySample.agent("w1:p1", .working)]
    private let idle = [LiveActivitySample.agent("w1:p1", .idle)]

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func appStartedActivity(_ harness: LiveActivityHarness, agents: [AgentSummary]) async throws -> DeviceID {
        let device = try await harness.pair()
        try await harness.registerUpdateToken(for: device)
        try await harness.agents(agents)
        return device
    }

    @Test func pushToStartBeginsTheActivityWhenAnAgentStartsWorking() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            try await harness.agents(idle)
            #expect(harness.sent.isEmpty)

            try await harness.agents(working)
            #expect(harness.sent.count == 1)
            let start = try harness.last()
            #expect(start.token == LiveActivitySample.pushToStartToken)
            #expect(start.environment == .sandbox)
            #expect(start.priority == .high)
            #expect(start.push.event == .start(alert: LiveActivityStartAlert(title: "Mocha", body: "1 trabalhando")))
            let highlight = LiveActivityContentState.Highlight(
                agentId: "w1:p1",
                title: "Refatorar o parser",
                workspaceLabel: "demo-app",
                status: "working",
                since: Sample.start
            )
            #expect(start.push.contentState == LiveActivityContentState(working: 1, waiting: 0, highlight: highlight, updatedAt: Sample.start))
            let aps = try harness.aps(start)
            #expect(aps["event"] as? String == "start")
            #expect(aps["attributes-type"] as? String == "MochaAgentsAttributes")
            #expect((aps["attributes"] as? [String: Any])?.isEmpty == true)
            #expect(aps["input-push-token"] as? Int == 1)
            let alert = try #require(aps["alert"] as? [String: Any])
            #expect(alert["title"] as? String == "Mocha")
            #expect(alert["body"] as? String == "1 trabalhando")
        }
    }

    @Test func onlyAWorkingClaudeAgentStartsTheActivity() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            try await harness.agents([LiveActivitySample.agent("w1:p1", .blocked)])
            try await harness.agents([LiveActivitySample.agent("w1:p2", .working, kind: "codex")])
            try await harness.agents([LiveActivitySample.agent("w1:p1", .idle, pendingCount: 1)])
            try await harness.advance(3600)
            #expect(harness.sent.isEmpty)
        }
    }

    @Test func aDeviceWithTheAppInTheForegroundGetsNoPushToStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working, foreground: [device])
            try await harness.advance(60)
            #expect(harness.sent.isEmpty)

            try await harness.agents(working)
            #expect(harness.sent.map(\.push.event.name) == ["start"])
        }
    }

    @Test func updatesWaitForTheTokenOfAPushStartedActivity() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working)
            try await harness.advance(5)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working, title: "Escrever testes")])
            try await harness.advance(30)
            #expect(harness.sent.count == 1)

            try await harness.registerUpdateToken(for: device)
            #expect(harness.sent.count == 2)
            let update = try harness.last()
            #expect(update.token == LiveActivitySample.updateToken)
            #expect(update.priority == .high)
            #expect(update.push.event == .update)
            #expect(update.push.contentState.working == 2)
            #expect(update.push.contentState.highlight?.agentId == "w1:p1")
            #expect(update.push.timestamp == at(35))
            #expect(update.push.staleDate == at(35 + 15 * 60))
            #expect(
                try await harness.storedRegistration(device) == LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    activityId: LiveActivitySample.activityId,
                    updateToken: LiveActivitySample.updateToken,
                    env: .sandbox
                )
            )
        }
    }

    @Test func anEarlyUpdateTokenStillWaitsTenSecondsAfterTheStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working)
            try await harness.advance(2)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working)])
            try await harness.advance(2)
            try await harness.registerUpdateToken(for: device)
            try await harness.advance(5)
            #expect(harness.sent.count == 1)

            try await harness.advance(1)
            #expect(harness.sent.count == 2)
            #expect(try harness.last().push.timestamp == at(10))
        }
    }

    @Test func aTokenForAnUnchangedStateSendsNothing() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working)
            try await harness.advance(20)
            try await harness.registerUpdateToken(for: device)
            try await harness.advance(60)
            #expect(harness.sent.map(\.push.event.name) == ["start"])
        }
    }

    @Test func updatesAreLimitedToOneEveryTenSecondsWithTheLatestState() async throws {
        try await withLiveActivity { harness in
            _ = try await appStartedActivity(harness, agents: working)
            #expect(harness.sent.count == 1)
            #expect(try harness.last().push.event == .update)

            try await harness.advance(3)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working)])
            try await harness.advance(3)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working), LiveActivitySample.agent("w3:p1", .working)])
            try await harness.advance(3)
            #expect(harness.sent.count == 1)

            try await harness.advance(1)
            #expect(harness.sent.count == 2)
            let update = try harness.last()
            #expect(update.push.contentState.working == 3)
            #expect(update.push.timestamp == at(10))

            try await harness.advance(10)
            #expect(harness.sent.count == 2)
        }
    }

    @Test func countAndHighlightChangesArePriorityTenAndATitleChangeIsFive() async throws {
        try await withLiveActivity { harness in
            let parser = LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o parser")
            let lexer = LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o lexer")
            let tests = LiveActivitySample.agent("w2:p1", .working, title: "Escrever testes")
            var blockedTests = tests
            blockedTests.status = .blocked
            var blockedLexer = lexer
            blockedLexer.status = .blocked
            var movedTests = tests
            movedTests.workspaceLabel = "outro"

            _ = try await appStartedActivity(harness, agents: [parser])
            try await harness.advance(10)
            try await harness.agents([parser, tests])
            try await harness.advance(10)
            try await harness.agents([lexer, tests])
            try await harness.advance(10)
            try await harness.agents([lexer, blockedTests])
            try await harness.advance(10)
            try await harness.agents([blockedLexer, tests])
            try await harness.advance(10)
            try await harness.agents([blockedLexer, movedTests])
            try await harness.advance(10)

            #expect(harness.sent.map(\.priority) == [.high, .high, .low, .high, .high])
            #expect(harness.sent.map { $0.push.contentState.highlight?.agentId } == ["w1:p1", "w1:p1", "w1:p1", "w2:p1", "w1:p1"])
            #expect(harness.sent.map { $0.push.contentState.highlight?.title } == [
                "Refatorar o parser", "Refatorar o parser", "Refatorar o lexer", "Escrever testes", "Refatorar o lexer",
            ])
            #expect(harness.sent.map(\.push.contentState.waiting) == [0, 0, 0, 1, 1])
            #expect(harness.sent.allSatisfy { $0.token == LiveActivitySample.updateToken && $0.push.event == .update })
        }
    }

    @Test func theHighlightTitleIsTruncatedToSixtyCharacters() async throws {
        try await withLiveActivity { harness in
            let title = String(repeating: "Título longo ", count: 8)
            _ = try await appStartedActivity(harness, agents: [LiveActivitySample.agent("w1:p1", .working, title: title)])
            #expect(try harness.last().push.contentState.highlight?.title == String(title.prefix(60)))
        }
    }

    @Test func endsSixtySecondsAfterTheLastAgentStopsWithTheFinalState() async throws {
        try await withLiveActivity { harness in
            let device = try await appStartedActivity(harness, agents: working)
            try await harness.advance(20)
            try await harness.agents(idle)
            #expect(harness.sent.count == 2)
            try await harness.advance(59)
            #expect(harness.sent.count == 2)

            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            let end = try harness.last()
            #expect(end.token == LiveActivitySample.updateToken)
            #expect(end.priority == .high)
            #expect(end.push.event == .end(dismissalDate: at(80 + 15 * 60)))
            #expect(end.push.contentState == LiveActivityContentState(working: 0, waiting: 0, highlight: nil, updatedAt: at(80)))
            #expect(end.push.staleDate == nil)
            #expect(
                try await harness.storedRegistration(device) == LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    env: .sandbox
                )
            )

            try await harness.registerUpdateToken(for: device)
            try await harness.advance(3600)
            #expect(harness.sent.count == 3)
            try await harness.agents(working)
            #expect(harness.sent.map(\.push.event.name) == ["update", "update", "end", "start"])
            #expect(try harness.last().token == LiveActivitySample.pushToStartToken)
        }
    }

    @Test func workingAgainWithinSixtySecondsKeepsTheActivity() async throws {
        try await withLiveActivity { harness in
            _ = try await appStartedActivity(harness, agents: working)
            try await harness.agents(idle)
            try await harness.advance(10)
            try await harness.advance(20)
            try await harness.agents(working)
            try await harness.advance(60)
            #expect(harness.sent.map(\.push.event.name) == ["update", "update", "update"])
            #expect(harness.sent.map(\.push.contentState.working) == [1, 0, 1])
            #expect(harness.sent.map(\.push.timestamp) == [at(0), at(10), at(30)])
        }
    }

    @Test func aBusyActivityIsRefreshedWithPriorityFiveEveryTenMinutes() async throws {
        try await withLiveActivity { harness in
            _ = try await appStartedActivity(harness, agents: [LiveActivitySample.agent("w1:p1", .blocked)])
            try await harness.advance(599)
            #expect(harness.sent.count == 1)

            try await harness.advance(1)
            #expect(harness.sent.count == 2)
            let refresh = try harness.last()
            #expect(refresh.priority == .low)
            #expect(refresh.push.event == .update)
            #expect(refresh.push.contentState.waiting == 1)
            #expect(refresh.push.timestamp == at(600))
            #expect(refresh.push.staleDate == at(600 + 15 * 60))

            try await harness.advance(600)
            #expect(harness.sent.map(\.priority) == [.high, .low, .low])
            #expect(try harness.last().push.staleDate == at(1200 + 15 * 60))
        }
    }

    @Test func renewsTheActivityAtSevenHoursFiftyMinutesWithAPushToStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working)
            try await harness.registerUpdateToken(for: device)
            for _ in 0..<46 {
                try await harness.advance(600)
            }
            try await harness.advance(599)
            #expect(harness.sent.count == 47)
            #expect(harness.sent.dropFirst().allSatisfy { $0.priority == .low && $0.push.event == .update })

            try await harness.advance(1)
            #expect(harness.sent.count == 49)
            let end = harness.sent[47]
            let start = harness.sent[48]
            #expect(end.token == LiveActivitySample.updateToken)
            #expect(end.priority == .high)
            #expect(end.push.event == .end(dismissalDate: at(28_200 + 15 * 60)))
            #expect(end.push.timestamp == at(7 * 3600 + 50 * 60))
            #expect(start.token == LiveActivitySample.pushToStartToken)
            #expect(start.priority == .high)
            #expect(start.push.event.name == "start")
            #expect(start.push.contentState.working == 1)
            #expect(start.push.timestamp == at(28_200))

            try await harness.registerUpdateToken(LiveActivitySample.otherUpdateToken, activityId: "segunda", for: device)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working)])
            try await harness.advance(10)
            #expect(try harness.last().token == LiveActivitySample.otherUpdateToken)
            #expect(try harness.last().push.contentState.working == 2)
        }
    }

    @Test func theRenewalSpendsAPushToStartFromTheBudget() async throws {
        let configuration = LiveActivityConfiguration(renewalAge: 120, pushToStartLimit: 2)
        try await withLiveActivity(configuration: configuration) { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working)
            try await harness.registerUpdateToken(for: device)
            try await harness.advance(120)
            try await harness.registerUpdateToken(LiveActivitySample.otherUpdateToken, activityId: "segunda", for: device)
            try await harness.advance(120)
            #expect(harness.sent.map(\.push.event.name) == ["start", "end", "start", "end"])
            #expect(harness.sent.map(\.push.timestamp) == [at(0), at(120), at(120), at(240)])

            try await harness.advance(3359)
            #expect(harness.sent.count == 4)
            try await harness.advance(1)
            #expect(harness.sent.map(\.push.event.name) == ["start", "end", "start", "end", "start"])
            #expect(try harness.last().push.timestamp == at(3600))
        }
    }

    @Test func atMostTenPushToStartsPerHour() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            for index in 0..<10 {
                try await harness.agents(working)
                #expect(harness.sent.count == index + 1)
                try await harness.agents(idle)
                try await harness.advance(60)
            }
            try await harness.agents(working)
            #expect(harness.sent.count == 10)
            try await harness.advance(2999)
            #expect(harness.sent.count == 10)

            try await harness.advance(1)
            #expect(harness.sent.count == 11)
            #expect(harness.sent.allSatisfy { $0.push.event.name == "start" && $0.token == LiveActivitySample.pushToStartToken })
            #expect(try harness.last().push.timestamp == at(3600))
        }
    }

    @Test func aRetryableFailureIsRetriedAfterTenSeconds() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            harness.sender.respond(with: .failed(retryable: true))
            try await harness.agents(working)
            try await harness.advance(9)
            #expect(harness.sent.count == 1)

            try await harness.advance(1)
            #expect(harness.sent.map(\.push.event.name) == ["start", "start"])
            try await harness.advance(3600)
            #expect(harness.sent.count == 2)
        }
    }

    @Test func aConfigurationFailureWaitsFiveMinutes() async throws {
        try await withLiveActivity { harness in
            _ = try await appStartedActivity(harness, agents: working)
            harness.sender.respond(with: .failed(retryable: false))
            try await harness.advance(10)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working)])
            try await harness.advance(299)
            #expect(harness.sent.count == 2)

            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.contentState.working == 2)
            #expect(try harness.last().push.timestamp == at(310))
        }
    }

    @Test func aRefusedPushToStartTokenIsForgotten() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            harness.sender.respond(with: .invalidToken)
            try await harness.agents(working)
            try await harness.advance(3600)
            #expect(harness.sent.count == 1)
            #expect(try await harness.storedRegistration(device) == nil)
        }
    }

    @Test func aRefusedUpdateTokenFallsBackToPushToStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            harness.sender.respond(with: .invalidToken)
            try await harness.agents(working)
            #expect(harness.sent.map(\.token) == [LiveActivitySample.updateToken, LiveActivitySample.pushToStartToken])
            #expect(harness.sent.map(\.push.event.name) == ["update", "start"])
            #expect(
                try await harness.storedRegistration(device) == LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    env: .sandbox
                )
            )
        }
    }

    @Test func anActivitySavedInDevicesJsonIsAdoptedOnStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            let saved = LiveActivityRegistration(
                pushToStartToken: LiveActivitySample.pushToStartToken,
                activityId: LiveActivitySample.activityId,
                updateToken: LiveActivitySample.updateToken,
                env: .production
            )
            #expect(try await harness.devices.setLiveActivity(saved, for: device))
            let (inputs, continuation) = AsyncStream.makeStream(of: LiveActivityInput.self)
            defer { continuation.finish() }
            await harness.service.start(inputs: inputs)
            continuation.yield(LiveActivityInput(agents: working))
            _ = try await eventually { harness.sent.isEmpty ? nil : true }
            try await harness.settle()

            #expect(harness.sent.count == 1)
            let update = try harness.last()
            #expect(update.token == LiveActivitySample.updateToken)
            #expect(update.environment == .production)
            #expect(update.priority == .high)
            #expect(update.push.event == .update)
        }
    }

    @Test func invalidTokensAreRejectedWithoutSavingAnything() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            for registration in [
                LiveActivityRegistration(pushToStartToken: "zz", env: .sandbox),
                LiveActivityRegistration(activityId: "a", updateToken: "abc", env: .sandbox),
                LiveActivityRegistration(pushToStartToken: LiveActivitySample.pushToStartToken, updateToken: "", env: .sandbox),
            ] {
                await #expect(throws: LiveActivityRegistrationError.invalidToken) {
                    try await harness.service.register(registration, from: device)
                }
            }
            #expect(try await harness.storedRegistration(device) == nil)
        }
    }

    @Test func tokensAreSavedInLowercaseAndUnknownDevicesAreIgnored() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.service.register(
                LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken.uppercased(),
                    activityId: "",
                    updateToken: LiveActivitySample.updateToken.uppercased(),
                    env: .sandbox
                ),
                from: device
            )
            #expect(
                try await harness.storedRegistration(device) == LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    updateToken: LiveActivitySample.updateToken,
                    env: .sandbox
                )
            )

            try await harness.service.register(LiveActivityRegistration(pushToStartToken: "0a", env: .sandbox), from: "sumiu")
            #expect(try await harness.devices.devices().map(\.id) == [device])
        }
    }

    @Test func aPushToStartTokenMovesToTheDeviceThatRegistersIt() async throws {
        try await withLiveActivity { harness in
            let phone = try await harness.pairWithPushToStart("iPhone")
            let pad = try await harness.pair("iPad")
            try await harness.service.register(
                LiveActivityRegistration(pushToStartToken: LiveActivitySample.pushToStartToken, env: .sandbox),
                from: pad
            )
            #expect(try await harness.storedRegistration(phone) == nil)
            #expect(try await harness.storedRegistration(pad)?.pushToStartToken == LiveActivitySample.pushToStartToken)

            try await harness.agents(working)
            #expect(harness.sent.count == 1)
        }
    }

    @Test func pushesStopForADeviceThatWasRemoved() async throws {
        try await withLiveActivity { harness in
            let device = try await appStartedActivity(harness, agents: working)
            #expect(try await harness.devices.remove(device))
            try await harness.advance(10)
            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working)])
            try await harness.advance(3600)
            #expect(harness.sent.count == 1)
        }
    }
}
