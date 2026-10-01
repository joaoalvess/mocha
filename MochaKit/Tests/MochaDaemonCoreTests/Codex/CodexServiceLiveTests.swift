import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

final class CodexThreadEventRecorder: Sendable {
    private let events = Mutex<[CodexThreadEvent]>([])

    func record(_ event: CodexThreadEvent) {
        events.withLock { $0.append(event) }
    }

    var all: [CodexThreadEvent] {
        events.withLock { $0 }
    }

    var items: [CodexItemEvent] {
        all.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    var turns: [CodexTurn] {
        all.compactMap { if case .turn(_, let turn, _) = $0 { turn } else { nil } }
    }
}

extension CodexServiceHarness {
    func replay(_ name: String) async throws {
        for message in try CodexLiveReplay.messages(name) {
            guard let method = message["method"]?.stringValue, let params = message["params"] else { continue }
            await server.notify(method, params: params)
        }
    }

    func recordThreadEvents(of service: CodexService) -> CodexThreadEventRecorder {
        let recorder = CodexThreadEventRecorder()
        let events = service.threadEvents()
        Task {
            for await event in events {
                recorder.record(event)
            }
        }
        return recorder
    }

    func serveEmptyPages() async {
        let empty = FakeCodexReply.result(.object([.init("data", .array([])), .init("nextCursor", .null)]))
        await server.reply(to: "thread/items/list", with: empty)
        await server.reply(to: "thread/turns/list", with: empty)
    }

    func serveResume() async throws {
        await server.reply(to: "thread/resume", with: .result(try CodexSample.result("thread-resume.response.json")))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct CodexServiceLiveTests {
    private func withBoundService(
        prepare: (CodexServiceHarness) async throws -> Void = { _ in },
        _ body: (CodexServiceHarness, CodexService, CodexUpdateRecorder, CodexThreadEventRecorder) async throws -> Void
    ) async throws {
        try await withCodexServer { harness in
            try await prepare(harness)
            let service = harness.makeService()
            let events = harness.recordThreadEvents(of: service)
            let updates = await harness.start(service)
            try await harness.bind(service)
            do {
                try await body(harness, service, updates, events)
            } catch {
                await service.stop()
                throw error
            }
            await service.stop()
        }
    }

    private static func resubscribed(_ events: CodexThreadEventRecorder) async throws {
        _ = try await eventually { events.all.contains(.resubscribed(threadId: CodexSample.threadId)) ? true : nil }
    }

    private static func isTurnDone(_ alert: CodexAlert) -> Bool {
        if case .turnDone = alert { true } else { false }
    }

    @Test func onlyACompletedTurnAlertsThatCodexFinished() async throws {
        try await withBoundService { harness, _, updates, _ in
            try await harness.replay("interrupted-turn")
            try await harness.replay("basic-turn")

            let done = try await eventually { updates.alerts.first(where: Self.isTurnDone) }
            #expect(done == .turnDone(CodexSample.pane, lastMessage: "OK2"))
            #expect(updates.alerts.count(where: Self.isTurnDone) == 1)
        }
    }

    @Test func aFailedTurnDoesNotAlertEither() async throws {
        try await withBoundService { harness, _, updates, events in
            let failed = try OrderedJSON.parse(Data(#"""
            {"threadId":"01a0f59e-6845-7403-880c-44a4e20672d1","turn":{"id":"t-falhou","items":[],"itemsView":"notLoaded","status":"failed","error":{"message":"stream disconnected"},"startedAt":1790827620,"completedAt":1790827621,"durationMs":900}}
            """#.utf8))
            await harness.server.notify("turn/completed", params: failed)
            try await harness.replay("basic-turn")

            _ = try await eventually { updates.alerts.first(where: Self.isTurnDone) }
            #expect(updates.alerts.count(where: Self.isTurnDone) == 1)
            let closing = try await eventually {
                events.all.lazy.compactMap { event -> ChatItem? in
                    guard case .turn(_, let turn, let items) = event, turn.id == "t-falhou" else { return nil }
                    return items.first
                }.first
            }
            #expect(closing.kind == .notice(text: "stream disconnected"))
        }
    }

    @Test func itemsAndTurnsAreStreamedForOtherWorkPackages() async throws {
        try await withBoundService { harness, service, _, events in
            try await harness.replay("command-turn")

            let footer = try await eventually { events.turns.first { $0.status == .completed } }
            #expect(footer.durationMs == 7_720)
            let commands = events.items.filter { $0.item["type"]?.stringValue == "commandExecution" }
            #expect(commands.map(\.isCompleted) == [false, true, false, true])
            #expect(commands.allSatisfy { $0.turnId == "01a0f5a1-4002-74e3-99de-cad3477bac9a" && $0.threadId == CodexSample.threadId })
            guard case .toolCall(let call) = commands.last?.chatItems.first?.kind else {
                Issue.record("o comando não virou toolCall")
                return
            }
            #expect(call.summary == "cat hello.txt")
            #expect(await service.threadSettings(for: CodexSample.threadId) == CodexThreadSettings(model: "gpt-6-luna", effort: "high", mode: "default"))
            #expect(events.all.contains(.settings(threadId: CodexSample.threadId, settings: CodexThreadSettings(model: "gpt-6-luna", effort: "high", mode: "default"))))
        }
    }

    @Test func theResumeGivesTheSettingsAndThePaneCarriesTheSummary() async throws {
        try await withBoundService(prepare: { try await $0.serveResume() }) { harness, service, updates, events in
            let resumed = try await eventually { await service.threadSettings(for: CodexSample.threadId).flatMap { $0.model == nil ? nil : $0 } }
            #expect(resumed == CodexThreadSettings(model: "gpt-6.1-sol", effort: nil, mode: "default"))
            _ = try await eventually { events.all.contains(.resubscribed(threadId: CodexSample.threadId)) ? true : nil }

            try await harness.replay("basic-turn")
            let pane = try await eventually {
                updates.panes[CodexSample.pane].flatMap { $0.summary.turnEndedAt != nil ? $0 : nil }
            }
            #expect(pane.title == "Responder OK1")
            #expect(pane.summary.branch == "s9-branch")
            #expect(pane.summary.preview == MessagePreview(author: .assistant, text: "OK2"))
            #expect(pane.summary.prompt == "Responda só: OK2")
            #expect(pane.summary.contextLeftPercent == 97)
            #expect(pane.settings.model == "gpt-6.1-sol")
            #expect(await service.threadSummary(for: CodexSample.threadId)?.contextUsedTokens == 20_136)
        }
    }

    @Test func theActiveTurnComesFromTheLiveStateWithoutReadingTheThread() async throws {
        try await withBoundService { harness, service, _, events in
            try await Self.resubscribed(events)
            let reads = await harness.server.requests(method: "thread/turns/list").count + harness.server.requests(method: "thread/items/list").count
            let started = try #require(try CodexLiveReplay.messages("command-turn").first { $0["method"]?.stringValue == "turn/started" })
            await harness.server.notify("turn/started", params: try #require(started["params"]))
            _ = try await eventually { events.turns.first }

            #expect(await service.activeTurnId(for: CodexSample.threadId) == "01a0f5a1-4002-74e3-99de-cad3477bac9a")
            #expect(await harness.server.requests(method: "thread/turns/list").count + harness.server.requests(method: "thread/items/list").count == reads)
        }
    }

    @Test func pagesUseItemCursorsAndDoNotCloseATurnTwice() async throws {
        try await withBoundService { harness, service, _, events in
            try await Self.resubscribed(events)
            let listed = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-items-list.response.json"))["result"])
            let turns = try #require(try OrderedJSON.parse(Fixtures.data("codex/pages/thread-turns-list.response.json"))["result"])
            let older = try OrderedJSON.parse(Data(#"""
            {"data":[{"turnId":"01a0f5a3-9897-7e41-8c29-41d1b3bfc6be","item":{"type":"userMessage","id":"u-velho","content":[{"type":"text","text":"Grave hello.txt","text_elements":[]}]},"startedAtMs":1790827534100,"completedAtMs":1790827534101}],"nextCursor":null,"backwardsCursor":null}
            """#.utf8))
            let firstCursor = try #require(listed["nextCursor"]?.stringValue)
            await harness.server.setHandler("thread/items/list") { request in
                request.string("cursor") == firstCursor ? .result(older) : .result(listed)
            }
            await harness.server.reply(to: "thread/turns/list", with: .result(turns))
            await harness.server.setHandler("thread/read", CodexSample.readReply([CodexSample.threadId: try #require(try CodexSample.result("thread-read.response.json")["thread"])]))

            let first = try await service.page(threadId: CodexSample.threadId, before: nil, limit: 5)
            #expect(first.items.count == 7)
            #expect(first.before == firstCursor)
            let request = try #require(await harness.server.requests(method: "thread/items/list").last)
            #expect(request.params["limit"] == .number("5"))
            #expect(request.string("sortDirection") == "desc")

            let second = try await service.page(threadId: CodexSample.threadId, before: firstCursor, limit: 5)
            #expect(second.items.map(\.id) == ["u-velho"])
            #expect(second.before == nil)
            #expect(await harness.server.requests(method: "thread/items/list").last?.string("cursor") == firstCursor)
        }
    }

    @Test func usageCarriesThePlanAndTheAccount() async throws {
        try await withCodexServer { harness in
            await harness.server.reply(to: "account/read", with: .result(try CodexSample.result("account-read.response.json")))
            await harness.server.reply(to: "account/rateLimits/read", with: .result(try OrderedJSON.parse(Fixtures.data("codex/rate-limits.json"))))
            let service = harness.makeService()
            let updates = await harness.start(service)

            let usage = try await eventually { updates.usages.first }
            #expect(usage.plan == "Plus")
            #expect(usage.account == "d•••@e•••.com")
            #expect(usage.provider == .codex)
            await service.stop()
        }
    }
}
