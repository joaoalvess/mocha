import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct CodexServiceBindingTests {
    @Test func aThreadStartedInTheExpectedPaneIsBoundSubscribedAndSaved() async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            let updates = await harness.start(service)
            try await harness.bind(service)

            _ = try await eventually { updates.panes[CodexSample.pane]?.threadId == CodexSample.threadId ? true : nil }
            #expect(CodexSample.savedBindings(in: harness.directory) == [
                CodexSample.pane: CodexPaneBinding(threadId: CodexSample.threadId, cwd: CodexSample.cwd),
            ])
            let file = harness.directory.appending(path: CodexPaneBindingStore.fileName).path(percentEncoded: false)
            let permissions = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? NSNumber
            #expect(permissions?.int16Value == 0o600)
            let resume = try #require(await harness.server.requests(method: "thread/resume").first)
            #expect(resume.params["excludeTurns"] == .bool(true))
            await service.stop()
        }
    }

    @Test func theEphemeralTitleThreadIsIgnored() async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            _ = await harness.start(service)
            try await harness.bind(service)

            await harness.server.notify("thread/started", params: try CodexSample.params("thread-started.ephemeral.json"))
            await harness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(CodexSample.thirdThreadId, parent: CodexSample.threadId)))
            try await Task.sleep(for: .milliseconds(100))
            #expect(await service.threadId(for: CodexSample.pane) == CodexSample.threadId)
            #expect(await harness.server.requests(method: "thread/unsubscribe").isEmpty)
            await service.stop()
        }
    }

    @Test func aRestartedDaemonRebindsThePaneAndTheRedeliveredRequestDoesNotPushAgain() async throws {
        try await withCodexServer { harness in
            let first = harness.makeService()
            let before = await harness.start(first)
            try await harness.bind(first)
            let request = CodexSample.setting(try CodexSample.params("command-execution-request-approval.json"), ["startedAtMs": CodexSample.nowMs()])
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 7, params: request)
            _ = try await eventually { before.pending.count == 1 ? true : nil }
            #expect(before.alerts.count == 1)
            await first.stop()

            await harness.server.reply(to: "thread/loaded/list", with: CodexSample.loaded([CodexSample.threadId]))
            let second = harness.makeService()
            let after = await harness.start(second)
            try await harness.waitForResume(of: CodexSample.threadId, count: 2)
            #expect(await second.threadId(for: CodexSample.pane) == CodexSample.threadId)
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 0, params: request)

            let pending = try await eventually { after.pending.first }
            #expect(pending.id == "codex:\(CodexSample.threadId):exec-e1e5e97c-f52c-4f69-beaf-f75504587451")
            #expect(pending.agentId == CodexSample.pane)
            _ = try await eventually { after.panes[CodexSample.pane]?.status == .blocked ? true : nil }

            try await second.respond(to: pending.id, with: .allow)
            let answer = try await eventually { await harness.server.clientResponses.last }
            #expect(answer.id == .number("0"))
            #expect(answer.result == .object([.init("decision", .string("accept"))]))
            try await Task.sleep(for: .milliseconds(100))
            #expect(after.alerts.isEmpty)
            await second.stop()
        }
    }

    @Test func reconnectingToTheAppServerResubscribesAndARedeliveredRequestStaysQuiet() async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            let updates = await harness.start(service)
            try await harness.bind(service)
            let request = CodexSample.setting(try CodexSample.params("command-execution-request-approval.json"), ["startedAtMs": CodexSample.nowMs()])
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 3, params: request)
            _ = try await eventually { updates.pending.count == 1 ? true : nil }

            await harness.server.stop()
            _ = try await eventually { updates.availability.last == false && updates.pending.isEmpty ? true : nil }
            #expect(updates.panes.isEmpty)

            await harness.server.reply(to: "thread/loaded/list", with: CodexSample.loaded([CodexSample.threadId]))
            try await harness.server.start()
            try await harness.waitForResume(of: CodexSample.threadId, count: 2)
            _ = try await eventually { updates.availability.last == true ? true : nil }
            await harness.server.serverRequest("item/commandExecution/requestApproval", id: 1, params: request)

            _ = try await eventually { updates.pending.count == 1 ? true : nil }
            #expect(updates.panes[CodexSample.pane]?.threadId == CodexSample.threadId)
            try await Task.sleep(for: .milliseconds(100))
            #expect(updates.alerts.count == 1)
            await service.stop()
        }
    }

    @Test func aMappedThreadOutsideTheLoadedListGivesThePaneTheOnlyOwnableThreadWithTheSameCwd() async throws {
        try await withCodexServer { harness in
            try CodexSample.bindings([CodexSample.pane: (CodexSample.threadId, CodexSample.cwd)], in: harness.directory)
            let title = "01a0f59e-a038-71a3-924d-60e161da9f17"
            let child = "01a0f5a6-0000-7000-8000-000000000001"
            await harness.server.reply(to: "thread/loaded/list", with: CodexSample.loaded([CodexSample.otherThreadId, CodexSample.thirdThreadId, title, child]))
            await harness.server.setHandler("thread/read", CodexSample.readReply([
                CodexSample.otherThreadId: CodexSample.thread(CodexSample.otherThreadId),
                CodexSample.thirdThreadId: CodexSample.thread(CodexSample.thirdThreadId, cwd: CodexSample.otherCwd),
                title: CodexSample.thread(title, ephemeral: true),
                child: CodexSample.thread(child, parent: CodexSample.otherThreadId),
            ]))
            let service = harness.makeService()
            _ = await harness.start(service)

            try await harness.waitForResume(of: CodexSample.otherThreadId)
            #expect(await service.threadId(for: CodexSample.pane) == CodexSample.otherThreadId)
            #expect(await harness.resumes(of: CodexSample.threadId) == 0)
            _ = try await eventually {
                CodexSample.savedBindings(in: harness.directory)[CodexSample.pane]?.threadId == CodexSample.otherThreadId ? true : nil
            }
            await service.stop()
        }
    }

    @Test func withoutAUniqueCandidateThePaneWaitsForTheNextThreadStartedInItsCwd() async throws {
        try await withCodexServer { harness in
            try CodexSample.bindings([CodexSample.pane: (CodexSample.threadId, CodexSample.cwd)], in: harness.directory)
            await harness.server.reply(to: "thread/loaded/list", with: CodexSample.loaded([CodexSample.otherThreadId, CodexSample.thirdThreadId]))
            await harness.server.setHandler("thread/read", CodexSample.readReply([
                CodexSample.otherThreadId: CodexSample.thread(CodexSample.otherThreadId),
                CodexSample.thirdThreadId: CodexSample.thread(CodexSample.thirdThreadId),
            ]))
            let service = harness.makeService()
            let updates = await harness.start(service)
            _ = try await eventually { await harness.server.requests(method: "thread/read").count == 2 ? true : nil }
            try await Task.sleep(for: .milliseconds(100))
            #expect(await service.threadId(for: CodexSample.pane) == nil)
            #expect(updates.panes.isEmpty)
            #expect(await harness.server.requests(method: "thread/resume").isEmpty)

            let fresh = "01a0f5a7-1111-7000-8000-000000000002"
            await harness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(fresh)))
            try await harness.waitForResume(of: fresh)
            #expect(await service.threadId(for: CodexSample.pane) == fresh)
            await service.stop()
        }
    }

    @Test func aNewThreadInTheSameCwdMovesThePaneAndUnsubscribesTheOldThread() async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            _ = await harness.start(service)
            try await harness.bind(service)

            await harness.server.notify("thread/started", params: CodexSample.started(CodexSample.thread(CodexSample.otherThreadId)))
            try await harness.waitForResume(of: CodexSample.otherThreadId)
            let unsubscribe = try await eventually { await harness.server.requests(method: "thread/unsubscribe").first }
            #expect(unsubscribe.string("threadId") == CodexSample.threadId)
            #expect(CodexSample.savedBindings(in: harness.directory)[CodexSample.pane]?.threadId == CodexSample.otherThreadId)
            await service.stop()
        }
    }

    @Test func aClosedPaneUnsubscribesItsThreadAndLeavesTheMap() async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            _ = await harness.start(service)
            try await harness.bind(service)

            await service.retainPanes([])
            let unsubscribe = try await eventually { await harness.server.requests(method: "thread/unsubscribe").first }
            #expect(unsubscribe.string("threadId") == CodexSample.threadId)
            #expect(CodexSample.savedBindings(in: harness.directory).isEmpty)
            await service.stop()
        }
    }

    @Test func paneMovedCarriesTheBindingTheRequestsAndTheMap() async throws {
        try await withCodexServer { harness in
            let service = harness.makeService()
            let updates = await harness.start(service)
            try await harness.bind(service)
            await harness.server.serverRequest(
                "item/commandExecution/requestApproval",
                id: 4,
                params: CodexSample.setting(try CodexSample.params("command-execution-request-approval.json"), ["startedAtMs": CodexSample.nowMs()])
            )
            _ = try await eventually { updates.pending.first?.agentId == CodexSample.pane ? true : nil }

            await service.movePane(from: CodexSample.pane, to: "w2:p9")
            #expect(await service.threadId(for: "w2:p9") == CodexSample.threadId)
            #expect(await service.threadId(for: CodexSample.pane) == nil)
            _ = try await eventually { updates.pending.first?.agentId == "w2:p9" ? true : nil }
            _ = try await eventually { updates.panes["w2:p9"]?.status == .blocked ? true : nil }
            #expect(CodexSample.savedBindings(in: harness.directory) == [
                "w2:p9": CodexPaneBinding(threadId: CodexSample.threadId, cwd: CodexSample.cwd),
            ])
            #expect(await harness.server.requests(method: "thread/unsubscribe").isEmpty)
            await service.stop()
        }
    }
}
