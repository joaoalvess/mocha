import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct LiveActivityServiceTests {
    private let working = [LiveActivitySample.agent("w1:p1", .working)]
    private let idle = [LiveActivitySample.agent("w1:p1", .idle)]
    private let pushToStart = LiveActivityRegistration(pushToStartToken: LiveActivitySample.pushToStartToken, env: .sandbox)

    private func at(_ seconds: TimeInterval) -> Date {
        Sample.start.addingTimeInterval(seconds)
    }

    private func appStartedActivity(_ harness: LiveActivityHarness, agents: [AgentSummary]) async throws -> DeviceID {
        let device = try await harness.pair()
        try await harness.registerUpdateToken(for: device)
        try await harness.agents(agents)
        return device
    }

    @Test func pushToStartBeginsAnActivityForEachAgentThatStartsWorking() async throws {
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
            #expect(start.push.agentId == "w1:p1")
            #expect(start.push.event == .start(alert: AgentActivityAlert(title: "Claude trabalhando · demo-app", body: "Refatorar o parser", sound: nil)))
            let highlight = LiveActivityContentState.Highlight(
                agentId: "w1:p1",
                title: "Refatorar o parser",
                workspaceLabel: "demo-app",
                status: "working",
                since: Sample.start
            )
            #expect(start.push.contentState == AgentActivityContentState(agent: highlight, pending: nil, updatedAt: Sample.start))
            #expect(start.push.staleDate == at(15 * 60))
            #expect(start.push.relevanceScore == 50)
            let aps = try harness.aps(start)
            #expect(aps["event"] as? String == "start")
            #expect(aps["attributes-type"] as? String == "MochaAgentAttributes")
            #expect(aps["attributes"] as? [String: String] == ["agentId": "w1:p1"])
            #expect(aps["input-push-token"] as? Int == 1)
            #expect(aps["relevance-score"] as? Double == 50)
            let alert = try #require(aps["alert"] as? [String: Any])
            #expect(alert["title"] as? String == "Claude trabalhando · demo-app")
            #expect(alert["body"] as? String == "Refatorar o parser")
            #expect(alert["sound"] == nil)

            try await harness.agents(working + [LiveActivitySample.agent("w2:p1", .working, title: "Escrever testes")])
            #expect(harness.sent.map(\.push.agentId) == ["w1:p1", "w2:p1"])
            #expect(try harness.last().push.event == .start(alert: AgentActivityAlert(title: "Claude trabalhando · demo-app", body: "Escrever testes", sound: nil)))
        }
    }

    @Test func onlyBusyClaudeAgentsGetAnActivity() async throws {
        try await withLiveActivity { harness in
            _ = try await harness.pairWithPushToStart()
            try await harness.agents([LiveActivitySample.agent("w1:p2", .working, kind: "codex"), LiveActivitySample.agent("w1:p1", .idle)])
            try await harness.advance(3600)
            #expect(harness.sent.isEmpty)

            try await harness.agents([LiveActivitySample.agent("w1:p1", .idle, pendingCount: 1)])
            #expect(harness.sent.map(\.push.event.name) == ["start"])
            #expect(try harness.last().push.contentState.agent.status == "blocked")
            #expect(try harness.last().push.relevanceScore == 100)
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
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o lexer")])
            try await harness.advance(30)
            #expect(harness.sent.count == 1)

            try await harness.registerUpdateToken(for: device)
            #expect(harness.sent.count == 2)
            let update = try harness.last()
            #expect(update.token == LiveActivitySample.updateToken)
            #expect(update.priority == .low)
            #expect(update.push.event == .update(alert: nil))
            #expect(update.push.contentState.agent.title == "Refatorar o lexer")
            #expect(update.push.timestamp == at(35))
            #expect(update.push.staleDate == at(35 + 15 * 60))
            #expect(try await harness.storedPushToStart(device) == pushToStart)
            #expect(try await harness.storedActivities(device) == [
                LiveActivityRegistration(activityId: LiveActivitySample.activityId, updateToken: LiveActivitySample.updateToken, agentId: "w1:p1", env: .sandbox),
            ])
        }
    }

    @Test func anUpdateTokenWithoutAnAgentIsIgnored() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.service.register(
                LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    activityId: LiveActivitySample.activityId,
                    updateToken: LiveActivitySample.updateToken,
                    env: .sandbox
                ),
                from: device
            )
            try await harness.agents(working)
            #expect(harness.sent.map(\.token) == [LiveActivitySample.pushToStartToken])
            #expect(try await harness.storedActivities(device).isEmpty)
        }
    }

    @Test func anEarlyUpdateTokenStillWaitsTenSecondsAfterTheStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            try await harness.agents(working)
            try await harness.advance(2)
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o lexer")])
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

    @Test func eachActivityIsLimitedToOneUpdateEveryTenSecondsWithTheLatestState() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(LiveActivitySample.token(1), activityId: "a1", agent: "w1:p1", for: device)
            try await harness.registerUpdateToken(LiveActivitySample.token(2), activityId: "a2", agent: "w2:p1", for: device)
            let tests = LiveActivitySample.agent("w2:p1", .working, title: "Escrever testes")
            func parser(_ title: String) -> AgentSummary {
                LiveActivitySample.agent("w1:p1", .working, title: title)
            }

            try await harness.agents([parser("Refatorar o parser"), tests])
            #expect(Set(harness.sent.map(\.token)) == [LiveActivitySample.token(1), LiveActivitySample.token(2)])
            try await harness.advance(3)
            try await harness.agents([parser("Refatorar o lexer"), tests])
            try await harness.advance(3)
            try await harness.agents([parser("Refatorar o scanner"), tests])
            try await harness.advance(3)
            #expect(harness.sent.count == 2)

            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            let update = try harness.last()
            #expect(update.token == LiveActivitySample.token(1))
            #expect(update.priority == .low)
            #expect(update.push.contentState.agent.title == "Refatorar o scanner")
            #expect(update.push.timestamp == at(10))

            try await harness.advance(2)
            var blockedTests = tests
            blockedTests.status = .blocked
            try await harness.agents([parser("Refatorar o scanner"), blockedTests])
            #expect(harness.sent.count == 4)
            let blocked = try harness.last()
            #expect(blocked.token == LiveActivitySample.token(2))
            #expect(blocked.priority == .high)
            #expect(blocked.push.timestamp == at(12))
            #expect(blocked.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "Esperando uma resposta no terminal.")))
            #expect(blocked.push.relevanceScore == 100)
        }
    }

    @Test func theTitleIsTruncatedToSixtyCharacters() async throws {
        try await withLiveActivity { harness in
            let title = String(repeating: "Título longo ", count: 8)
            _ = try await appStartedActivity(harness, agents: [LiveActivitySample.agent("w1:p1", .working, title: title)])
            #expect(try harness.last().push.contentState.agent.title == String(title.prefix(60)))
        }
    }

    @Test func endsThirtyMinutesAfterTheAgentStopsAndLeavesAtOnce() async throws {
        try await withLiveActivity { harness in
            let device = try await appStartedActivity(harness, agents: working)
            try await harness.advance(20)
            try await harness.agents(idle)
            #expect(harness.sent.count == 2)
            let done = try harness.last()
            #expect(done.priority == .high)
            #expect(done.push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Turno concluído.")))
            #expect(done.push.contentState.agent.status == "idle")
            #expect(done.push.relevanceScore == 10)
            try await harness.advance(1799)
            #expect(harness.sent.count == 2)

            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            let end = try harness.last()
            #expect(end.token == LiveActivitySample.updateToken)
            #expect(end.priority == .high)
            #expect(end.push.event == .end(dismissalDate: at(1820)))
            #expect(end.push.contentState.agent.status == "idle")
            #expect(end.push.staleDate == nil)
            #expect(try await harness.storedActivities(device).isEmpty)
            #expect(try await harness.storedPushToStart(device) == pushToStart)

            try await harness.registerUpdateToken(for: device)
            try await harness.advance(3600)
            #expect(harness.sent.count == 3)
            try await harness.agents(working)
            #expect(harness.sent.map(\.push.event.name) == ["update", "update", "end", "start"])
            #expect(try harness.last().token == LiveActivitySample.pushToStartToken)
        }
    }

    @Test func workingAgainWithinThirtyMinutesKeepsTheActivity() async throws {
        try await withLiveActivity { harness in
            _ = try await appStartedActivity(harness, agents: working)
            try await harness.advance(10)
            try await harness.agents(idle)
            try await harness.advance(1000)
            try await harness.agents(working)
            try await harness.advance(600)
            try await harness.advance(400)
            #expect(harness.sent.map(\.push.event.name) == ["update", "update", "update", "update"])
            #expect(harness.sent.map(\.push.contentState.agent.status) == ["working", "idle", "working", "working"])
            #expect(harness.sent.map(\.push.timestamp) == [at(0), at(10), at(1010), at(1610)])
        }
    }

    @Test func anAgentThatLeavesTheTreeEndsItsActivity() async throws {
        try await withLiveActivity { harness in
            let device = try await appStartedActivity(harness, agents: working)
            try await harness.advance(4)
            try await harness.agents([])
            #expect(harness.sent.count == 1)

            try await harness.advance(6)
            #expect(harness.sent.count == 2)
            let end = try harness.last()
            #expect(end.push.event == .end(dismissalDate: at(10)))
            #expect(end.push.contentState.agent.title == "Refatorar o parser")
            #expect(try await harness.storedActivities(device).isEmpty)
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
            #expect(refresh.push.event == .update(alert: nil))
            #expect(refresh.push.contentState.agent.status == "blocked")
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
            #expect(harness.sent.dropFirst().allSatisfy { $0.priority == .low && $0.push.event == .update(alert: nil) })

            try await harness.advance(1)
            #expect(harness.sent.count == 49)
            let end = harness.sent[47]
            let start = harness.sent[48]
            #expect(end.token == LiveActivitySample.updateToken)
            #expect(end.priority == .high)
            #expect(end.push.event == .end(dismissalDate: at(28_200)))
            #expect(end.push.timestamp == at(7 * 3600 + 50 * 60))
            #expect(start.token == LiveActivitySample.pushToStartToken)
            #expect(start.priority == .high)
            #expect(start.push.event.name == "start")
            #expect(start.push.agentId == "w1:p1")
            #expect(start.push.timestamp == at(28_200))

            try await harness.registerUpdateToken(LiveActivitySample.otherUpdateToken, activityId: "segunda", for: device)
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o lexer")])
            try await harness.advance(10)
            #expect(try harness.last().token == LiveActivitySample.otherUpdateToken)
            #expect(try harness.last().push.contentState.agent.title == "Refatorar o lexer")
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
        try await withLiveActivity(configuration: LiveActivityConfiguration(activityLimit: 20)) { harness in
            _ = try await harness.pairWithPushToStart()
            var agents: [AgentSummary] = []
            for index in 0..<11 {
                agents.append(LiveActivitySample.agent("w\(index):p1", .working))
                try await harness.agents(agents)
                #expect(harness.sent.count == min(index + 1, 10))
                try await harness.advance(60)
            }
            try await harness.advance(2939)
            #expect(harness.sent.count == 10)

            try await harness.advance(1)
            #expect(harness.sent.count == 11)
            #expect(harness.sent.allSatisfy { $0.push.event.name == "start" && $0.token == LiveActivitySample.pushToStartToken })
            #expect(try harness.last().push.agentId == "w10:p1")
            #expect(try harness.last().push.timestamp == at(3600))
        }
    }

    @Test func atMostFiveActivitiesAndABlockedAgentTakesTheSlotOfTheOldestIdleOne() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pairWithPushToStart()
            let ids = (1...7).map { "w\($0):p1" }
            func agents(_ statuses: [AgentStatus]) -> [AgentSummary] {
                zip(ids, statuses).map { LiveActivitySample.agent($0, $1) }
            }

            try await harness.agents(agents(Array(repeating: .working, count: 6)))
            #expect(harness.sent.map(\.push.agentId).sorted() == Array(ids.prefix(5)))
            for (index, id) in ids.prefix(5).enumerated() {
                try await harness.registerUpdateToken(LiveActivitySample.token(index + 1), activityId: "a\(index + 1)", agent: id, for: device)
            }
            try await harness.advance(20)
            try await harness.agents(agents([.idle, .working, .working, .working, .working, .working]))
            try await harness.advance(10)
            try await harness.agents(agents([.idle, .idle, .working, .working, .working, .working]))
            try await harness.advance(10)
            #expect(harness.sent.count == 7)

            try await harness.agents(agents([.idle, .idle, .working, .working, .working, .blocked, .working]))
            let tail = Array(harness.sent.dropFirst(7))
            #expect(tail.map(\.push.event.name) == ["end", "start"])
            #expect(tail.map(\.push.agentId) == ["w1:p1", "w6:p1"])
            #expect(tail.first?.token == LiveActivitySample.token(1))
            #expect(tail.last?.push.relevanceScore == 100)

            try await harness.advance(60)
            #expect(!harness.sent.contains { $0.push.agentId == "w7:p1" })
            #expect(try await harness.storedActivities(device).compactMap(\.agentId) == ["w2:p1", "w3:p1", "w4:p1", "w5:p1"])
        }
    }

    @Test func aNewRequestAndAFinishedTurnAlertThroughTheActivity() async throws {
        try await withLiveActivity { harness in
            _ = try await appStartedActivity(harness, agents: working)
            try await harness.advance(10)
            let request = LiveActivitySample.permission("req-1", agent: "w1:p1")
            try await harness.agents([LiveActivitySample.agent("w1:p1", .blocked)], pending: [request])
            let ask = try harness.last()
            #expect(ask.priority == .high)
            #expect(ask.push.event == .update(alert: AgentActivityAlert(title: "Claude precisa de você · demo-app", body: "rm -rf build")))
            #expect(ask.push.contentState.pending?.requestId == "req-1")
            let alert = try #require(try harness.aps(ask)["alert"] as? [String: Any])
            #expect(alert["title"] as? String == "Claude precisa de você · demo-app")
            #expect(alert["body"] as? String == "rm -rf build")
            #expect(alert["sound"] as? String == "default")

            try await harness.advance(10)
            try await harness.agents(working)
            #expect(try harness.last().push.event == .update(alert: nil))
            try await harness.advance(10)
            var finished = LiveActivitySample.agent("w1:p1", .idle)
            finished.preview = MessagePreview(author: .assistant, text: "**Pronto**: rodei os testes.")
            try await harness.agents([finished])
            #expect(try harness.last().push.event == .update(alert: AgentActivityAlert(title: "Claude terminou · demo-app", body: "Pronto: rodei os testes.")))
            #expect(harness.sent.map(\.priority) == [.high, .high, .high, .high])
        }
    }

    @Test func theTurnDoneAlertFollowsThePreferenceAndTheForegroundGetsNoAlert() async throws {
        try await withLiveActivity { harness in
            let device = try await appStartedActivity(harness, agents: working)
            #expect(try await harness.devices.setPreferences(DevicePreferences(turnDoneAlerts: false), for: device))
            try await harness.advance(10)
            try await harness.agents(idle)
            #expect(try harness.last().push.event == .update(alert: nil))
            #expect(try harness.last().priority == .high)

            try await harness.advance(10)
            let request = LiveActivitySample.permission("req-1", agent: "w1:p1")
            try await harness.agents([LiveActivitySample.agent("w1:p1", .blocked)], pending: [request], foreground: [device])
            #expect(try harness.last().push.event == .update(alert: nil))
            #expect(try harness.last().push.contentState.pending?.requestId == "req-1")
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
            try await harness.agents([LiveActivitySample.agent("w1:p1", .working, title: "Refatorar o lexer")])
            try await harness.advance(299)
            #expect(harness.sent.count == 2)

            try await harness.advance(1)
            #expect(harness.sent.count == 3)
            #expect(try harness.last().push.contentState.agent.title == "Refatorar o lexer")
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
            #expect(try await harness.storedPushToStart(device) == nil)
        }
    }

    @Test func aRefusedUpdateTokenWaitsForTheNextTurnToStartAgain() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            try await harness.registerUpdateToken(for: device)
            harness.sender.respond(with: .invalidToken)
            try await harness.agents(working)
            try await harness.advance(60)
            #expect(harness.sent.map(\.push.event.name) == ["update"])
            #expect(try await harness.storedActivities(device).isEmpty)
            #expect(try await harness.storedPushToStart(device) == pushToStart)

            try await harness.agents(idle)
            try await harness.agents(working)
            #expect(harness.sent.map(\.push.event.name) == ["update", "start"])
            #expect(try harness.last().token == LiveActivitySample.pushToStartToken)
        }
    }

    @Test func activitiesSavedInDevicesJsonAreAdoptedOnStart() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            #expect(try await harness.devices.setLiveActivities(
                pushToStart: LiveActivityRegistration(
                    pushToStartToken: LiveActivitySample.pushToStartToken,
                    activityId: "agregada",
                    updateToken: LiveActivitySample.otherUpdateToken,
                    env: .production
                ),
                agentActivities: [
                    LiveActivityRegistration(activityId: LiveActivitySample.activityId, updateToken: LiveActivitySample.updateToken, agentId: "w1:p1", env: .production),
                ],
                for: device
            ))
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
            #expect(update.push.event == .update(alert: nil))
        }
    }

    @Test func invalidTokensAreRejectedWithoutSavingAnything() async throws {
        try await withLiveActivity { harness in
            let device = try await harness.pair()
            for registration in [
                LiveActivityRegistration(pushToStartToken: "zz", env: .sandbox),
                LiveActivityRegistration(activityId: "a", updateToken: "abc", agentId: "w1:p1", env: .sandbox),
                LiveActivityRegistration(pushToStartToken: LiveActivitySample.pushToStartToken, updateToken: "", agentId: "w1:p1", env: .sandbox),
            ] {
                await #expect(throws: LiveActivityRegistrationError.invalidToken) {
                    try await harness.service.register(registration, from: device)
                }
            }
            #expect(try await harness.storedPushToStart(device) == nil)
            #expect(try await harness.storedActivities(device).isEmpty)
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
                    agentId: "w1:p1",
                    env: .sandbox
                ),
                from: device
            )
            #expect(try await harness.storedPushToStart(device) == pushToStart)
            #expect(try await harness.storedActivities(device) == [
                LiveActivityRegistration(updateToken: LiveActivitySample.updateToken, agentId: "w1:p1", env: .sandbox),
            ])

            try await harness.service.register(LiveActivityRegistration(pushToStartToken: "0a", env: .sandbox), from: "sumiu")
            #expect(try await harness.devices.devices().map(\.id) == [device])
        }
    }

    @Test func tokensMoveToTheDeviceThatRegistersThem() async throws {
        try await withLiveActivity { harness in
            let phone = try await harness.pair("iPhone")
            try await harness.registerUpdateToken(for: phone)
            let pad = try await harness.pair("iPad")
            try await harness.registerUpdateToken(for: pad)
            #expect(try await harness.storedPushToStart(phone) == nil)
            #expect(try await harness.storedActivities(phone).isEmpty)
            #expect(try await harness.storedPushToStart(pad) == pushToStart)
            #expect(try await harness.storedActivities(pad).map(\.agentId) == ["w1:p1"])

            try await harness.agents(working)
            #expect(harness.sent.count == 1)
        }
    }

    @Test func pushesStopForADeviceThatWasRemoved() async throws {
        try await withLiveActivity { harness in
            let device = try await appStartedActivity(harness, agents: working)
            #expect(try await harness.devices.remove(device))
            try await harness.advance(10)
            try await harness.agents([LiveActivitySample.agent("w1:p1", .blocked)])
            try await harness.advance(3600)
            #expect(harness.sent.count == 1)
        }
    }
}
