import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PendingSequenceTests {
    static func expectDecision(_ response: HttpResponse, equals body: OrderedJSON) throws {
        #expect(response.status == .ok)
        #expect(response.headers["Content-Type"] == "application/json")
        #expect(try OrderedJSON.parse(response.body) == body)
        #expect(response.body == Data(body.prettyPrinted().utf8))
    }

    static func expectNoDecision(_ response: HttpResponse) {
        #expect(response.status == .ok)
        #expect(response.headers["Content-Type"] == "application/json")
        #expect(String(decoding: response.body, as: UTF8.self) == "{}")
    }

    @Test func phoneAllowAnswersTheHeldHookWithTheAllowBody() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay("sequence.permission.phone-allow.jsonl", fixture: "PermissionRequest.bash.json", session: PendingSample.bashSession)

            let body = try #require(replay.phoneBody)
            try Self.expectDecision(await replay.held.response(), equals: body)
            #expect(body == PendingHookReply.allow())
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .phone)
            #expect(await harness.store.requests.isEmpty)
        }
    }

    @Test func phoneDenyAnswersWithTheMessageAndTheTurnGoesOn() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay("sequence.permission.phone-deny.jsonl", fixture: "PermissionRequest.bash.json", session: PendingSample.bashSession)

            let body = try #require(replay.phoneBody)
            try Self.expectDecision(await replay.held.response(), equals: body)
            #expect(body == PendingHookReply.deny("Negado pelo celular: não crie arquivos agora"))
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .phone)
        }
    }

    @Test func phoneAnswersFillEveryQuestionAndKeepTheOriginalQuestions() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay(
                "sequence.question.hook-answer.jsonl",
                fixture: "PermissionRequest.AskUserQuestion.multi.json",
                session: PendingSample.questionSession
            )

            let body = try #require(replay.phoneBody)
            try Self.expectDecision(await replay.held.response(), equals: body)
            #expect(body == PendingSample.withoutTrailingNewline(try PendingSample.fixture("response.PermissionRequest.AskUserQuestion.multi.json")).orderedJSON)
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .phone)
        }
    }

    @Test func phoneAnswersAfterAnExpiredPreToolUseStillReachTheHook() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay(
                "sequence.question.pretooluse-hold-timeout.jsonl",
                fixture: "PermissionRequest.AskUserQuestion.single.json",
                session: PendingSample.questionSession
            )

            let body = try #require(replay.phoneBody)
            try Self.expectDecision(await replay.held.response(), equals: body)
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .phone)
        }
    }

    @Test func terminalYesIsNoticedByTheHerdrStatusLeavingBlocked() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay("sequence.permission.terminal-allow.jsonl", fixture: "PermissionRequest.bash.json", session: PendingSample.bashSession)

            Self.expectNoDecision(await replay.held.response())
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .terminalStatus)
            #expect(replay.phoneBody == nil)
            #expect(replay.lateRespondErrors == [.requestNotFound])
            #expect(await harness.store.requests.isEmpty)
        }
    }

    @Test func terminalYesIsNoticedByTheToolResultWithoutHerdr() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay(
                "sequence.permission.terminal-allow.jsonl",
                fixture: "PermissionRequest.bash.json",
                session: PendingSample.bashSession,
                skipping: { $0.source == "herdr" }
            )

            Self.expectNoDecision(await replay.held.response())
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .terminalTranscript)
            #expect(replay.lateRespondErrors == [.requestNotFound])
        }
    }

    @Test func terminalOptionOfAQuestionIsNoticedByTheToolResult() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay(
                "sequence.question.terminal-answer.jsonl",
                fixture: "PermissionRequest.AskUserQuestion.single.json",
                session: PendingSample.questionSession
            )

            Self.expectNoDecision(await replay.held.response())
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .terminalTranscript)
        }
    }

    @Test func terminalNoClosesTheConnectionAndRemovesTheRequest() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay("sequence.permission.terminal-no.jsonl", fixture: "PermissionRequest.bash.json", session: PendingSample.bashSession)

            #expect(try await harness.resolution(of: replay.held.requestId).reason == .connectionClosed)
            #expect(await harness.store.requests.isEmpty)
            #expect(await harness.store.recentResolutions.count == 1)
        }
    }

    @Test func terminalEscOnAQuestionClosesTheConnectionAndRemovesTheRequest() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay(
                "sequence.question.terminal-esc.jsonl",
                fixture: "PermissionRequest.AskUserQuestion.single.json",
                session: PendingSample.questionSession
            )

            #expect(try await harness.resolution(of: replay.held.requestId).reason == .connectionClosed)
            #expect(await harness.store.requests.isEmpty)
        }
    }

    @Test func after580SecondsTheDaemonAnswersWithoutDeciding() async throws {
        try await withPendingStore { harness in
            let replay = try await harness.replay(
                "sequence.permission.timeout.jsonl",
                fixture: "PermissionRequest.bash.json",
                session: PendingSample.bashSession,
                skipping: { $0.dt > 60 }
            )
            let request = try #require(await harness.store.requests.first)
            #expect(request.id == replay.held.requestId)
            let remaining = request.createdAt.addingTimeInterval(580).timeIntervalSince(harness.clock.now())
            harness.clock.advance(by: .milliseconds(Int64((remaining * 1000).rounded()) - 1))
            #expect(await harness.store.contains(replay.held.requestId))
            harness.clock.advance(by: .milliseconds(1))

            Self.expectNoDecision(await replay.held.response())
            #expect(try await harness.resolution(of: replay.held.requestId).reason == .timeout)
            #expect(await harness.store.requests.isEmpty)
        }
    }
}

extension Data {
    var orderedJSON: OrderedJSON? {
        try? OrderedJSON.parse(self)
    }
}
