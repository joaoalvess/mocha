import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct PendingStoreTests {
    @Test func creationPublishesTheHookWithTheRequestIdAndTheRequestFields() async throws {
        try await withPendingStore { harness in
            var hooks = harness.hooks.events().makeAsyncIterator()
            harness.clock.advance(by: .seconds(3))

            let held = try await harness.hold("PermissionRequest.bash.json")

            let published = try #require(await hooks.next())
            #expect(published.requestId == held.requestId)
            #expect(published.agentId == PendingSample.agent)
            #expect(published.event.name == .permissionRequest)
            let request = try #require(await harness.store.requests.first)
            #expect(request == PendingRequest(
                id: held.requestId,
                agentId: PendingSample.agent,
                createdAt: Sample.start.addingTimeInterval(3),
                kind: .permission(toolName: "Bash", summary: "touch f.txt", inputJSON: #"{"command":"touch f.txt","description":"Create an empty file named f.txt"}"#)
            ))
            let opened = try #require(await harness.transcripts.openRequests.last)
            #expect(opened.session == TranscriptSession(
                sessionId: PendingSample.bashSession,
                transcriptPath: "/Users/dev/.claude/projects/-Users-dev-projects-demo-app/\(PendingSample.bashSession).jsonl"
            ))
        }
    }

    @Test func aSecondRequestOfTheSameSessionReplacesTheFirstWithoutDeciding() async throws {
        try await withPendingStore { harness in
            let first = try await harness.hold("PermissionRequest.write.json")
            harness.clock.advance(by: .seconds(1))
            let other = try await harness.hold("PermissionRequest.bash.json", pane: "w1:p2")
            harness.clock.advance(by: .seconds(1))

            let second = try await harness.hold("PermissionRequest.AskUserQuestion.single.json")

            #expect(String(decoding: await first.response().body, as: UTF8.self) == "{}")
            #expect(try await harness.resolution(of: first.requestId).reason == .sessionHook(.permissionRequest))
            #expect(Set(await harness.store.requests.map(\.id)) == [other.requestId, second.requestId])
            #expect(await harness.store.requests.map(\.agentId) == ["w1:p2", PendingSample.agent])
        }
    }

    @Test func userPromptSubmitAndStopOfTheSameSessionEndTheRequest() async throws {
        try await withPendingStore { harness in
            for (name, file) in [(HookEventName.userPromptSubmit, "UserPromptSubmit.json"), (.stop, "Stop.json")] {
                let held = try await harness.hold("PermissionRequest.bash.json")
                let untouched = try await harness.hold("PermissionRequest.AskUserQuestion.single.json", pane: "w1:p2")

                try await harness.post(name, file, session: "44444444-4444-4444-8444-444444444444")
                try await harness.post(.notification, "Notification.permission_prompt.json", session: PendingSample.bashSession)
                #expect(await harness.store.contains(held.requestId))
                try await harness.post(name, file, session: PendingSample.bashSession)

                #expect(String(decoding: await held.response().body, as: UTF8.self) == "{}")
                #expect(try await harness.resolution(of: held.requestId).reason == .sessionHook(name))
                #expect(await harness.store.requests.map(\.id) == [untouched.requestId])
                try await harness.closeAndWait(untouched)
            }
        }
    }

    @Test func aSecondResponseToTheSameRequestIsNotFound() async throws {
        try await withPendingStore { harness in
            let held = try await harness.hold("PermissionRequest.bash.json")

            try await harness.store.respond(to: held.requestId, with: .allow)

            await #expect(throws: PendingRespondError.requestNotFound) {
                try await harness.store.respond(to: held.requestId, with: .deny(reason: nil))
            }
            await #expect(throws: PendingRespondError.requestNotFound) {
                try await harness.store.respond(to: "desconhecido", with: .allow)
            }
            #expect(try OrderedJSON.parse(await held.response().body) == PendingHookReply.allow())
        }
    }

    @Test func anInvalidResponseKeepsTheRequestOpen() async throws {
        try await withPendingStore { harness in
            let question = try await harness.hold("PermissionRequest.AskUserQuestion.multi.json")

            await #expect(throws: PendingRespondError.invalidPayload(PendingHookReply.allowOnQuestion)) {
                try await harness.store.respond(to: question.requestId, with: .allow)
            }
            await #expect(throws: PendingRespondError.invalidPayload(PendingHookReply.missingAnswer("Quais testes?"))) {
                try await harness.store.respond(to: question.requestId, with: .answers(["Qual editor?": ["Vim"], "Qual tema?": ["Claro"]]))
            }
            #expect(await harness.store.contains(question.requestId))

            try await harness.store.respond(to: question.requestId, with: .answers(["Qual editor?": ["Vim"], "Quais testes?": ["UI"], "Qual tema?": ["Claro"]]))
            let answers = try OrderedJSON.parse(await question.response().body)["hookSpecificOutput"]?["decision"]?["updatedInput"]?["answers"]
            #expect(answers == .object([
                OrderedJSON.Member("Qual editor?", .string("Vim")),
                OrderedJSON.Member("Quais testes?", .string("UI")),
                OrderedJSON.Member("Qual tema?", .string("Claro")),
            ]))
        }
    }

    @Test func blockedBeforeTheRequestDoesNotCountAsAnAnswer() async throws {
        try await withPendingStore { harness in
            try await harness.emitStatus(.blocked)
            let held = try await harness.hold("PermissionRequest.bash.json")

            try await harness.emitStatus(.working)
            try await harness.emitStatus(.blocked, agent: "w1:p2")
            try await harness.emitStatus(.working, agent: "w1:p2")
            #expect(await harness.store.contains(held.requestId))

            try await harness.emitStatus(.blocked)
            try await harness.emitStatus(.blocked)
            #expect(await harness.store.contains(held.requestId))
            try await harness.emitStatus(.done)

            #expect(try await harness.resolution(of: held.requestId).reason == .terminalStatus)
        }
    }

    @Test func anOlderToolResultOfTheSameToolIsNotAnAnswer() async throws {
        try await withPendingStore(configure: { transcripts in
            await transcripts.setPage(
                Sample.page([
                    PendingSample.toolCall("toolu_old", name: "Bash", status: .succeeded),
                    PendingSample.toolCall("toolu_running", name: "Bash", status: .running),
                    PendingSample.toolCall("toolu_read", name: "Read", status: .running),
                ]),
                forSession: PendingSample.bashSession
            )
        }) { harness in
            let held = try await harness.hold("PermissionRequest.bash.json")
            let session = PendingSample.bashSession

            try await harness.emitTranscript(.update([PendingSample.toolCall("toolu_old", name: "Bash", status: .succeeded)]), session: session, watched: true)
            try await harness.emitTranscript(.update([PendingSample.toolCall("toolu_read", name: "Read", status: .succeeded)]), session: session, watched: true)
            try await harness.emitTranscript(.append([PendingSample.toolCall("toolu_new", name: "Bash", status: .running)]), session: session, watched: true)
            try await harness.emitTranscript(.update([PendingSample.toolCall("toolu_running", name: "Bash", status: .succeeded)]), session: session, watched: true)
            #expect(await harness.store.contains(held.requestId))

            try await harness.emitTranscript(.update([PendingSample.toolCall("toolu_new", name: "Bash", status: .failed)]), session: session, watched: true)

            #expect(try await harness.resolution(of: held.requestId).reason == .terminalTranscript)
            _ = try await eventually { await harness.transcripts.subscriberCount(forSession: session) == 0 ? true : nil }
        }
    }

    @Test func aPaneMovedCarriesTheRequestToTheNewAgentId() async throws {
        try await withPendingStore { harness in
            let held = try await harness.hold("PermissionRequest.bash.json")
            var updates = harness.store.updates().makeAsyncIterator()
            _ = await updates.next()

            try await harness.observing { harness.herdr.movePane(from: PendingSample.agent, to: "w2:p1") }

            #expect(await updates.next()?.map(\.agentId) == ["w2:p1"])
            try await harness.emitStatus(.blocked, agent: "w2:p1")
            try await harness.emitStatus(.working, agent: "w2:p1")
            #expect(try await harness.resolution(of: held.requestId).reason == .terminalStatus)

            let moved = try await harness.hold("PermissionRequest.bash.json", pane: PendingSample.agent)
            #expect(await harness.store.requests.first { $0.id == moved.requestId }?.agentId == "w2:p1")
        }
    }

    @Test func aSubagentRequestDoesNotWatchTheMainTranscript() async throws {
        try await withPendingStore { harness in
            let body = try PendingSample.json("PermissionRequest.bash.json").setting("agent_id", to: .string("a0123456789abcdef"))
            let server = harness.server
            let task = Task { await server.respond(to: PendingSample.hookRequest(.permissionRequest, body: Data(body.compactSerialized().utf8)), as: .permissionRequest) }
            let requestId = try await eventually { await harness.store.requests.first?.id }

            #expect(await harness.transcripts.openRequests.isEmpty)
            #expect(await harness.store.isWatchingTranscript(requestId) == false)
            try await harness.store.respond(to: requestId, with: .allow)
            #expect(try OrderedJSON.parse(await task.value.body) == PendingHookReply.allow())
        }
    }

    @Test func hooksOutsideHerdrAreNotHeld() async throws {
        try await withPendingStore { harness in
            let response = await harness.server.respond(
                to: PendingSample.hookRequest(.permissionRequest, body: try PendingSample.fixture("PermissionRequest.bash.json"), pane: ""),
                as: .permissionRequest
            )
            #expect(String(decoding: response.body, as: UTF8.self) == "{}")
            #expect(await harness.store.requests.isEmpty)
        }
    }

    @Test func shutdownAnswersEveryHeldHookWithoutDeciding() async throws {
        try await withPendingStore { harness in
            let bash = try await harness.hold("PermissionRequest.bash.json")
            let question = try await harness.hold("PermissionRequest.AskUserQuestion.single.json")

            await harness.store.shutdown()

            #expect(String(decoding: await bash.response().body, as: UTF8.self) == "{}")
            #expect(String(decoding: await question.response().body, as: UTF8.self) == "{}")
            #expect(await harness.store.requests.isEmpty)
            #expect(await harness.store.recentResolutions.map(\.reason) == [.shutdown, .shutdown])
            let late = await harness.server.respond(
                to: PendingSample.hookRequest(.permissionRequest, body: try PendingSample.fixture("PermissionRequest.write.json")),
                as: .permissionRequest
            )
            #expect(String(decoding: late.body, as: UTF8.self) == "{}")
        }
    }
}
