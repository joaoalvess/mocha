import Foundation
import MochaProtocol
import MochaTestSupport
import MochaTranscript
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(2)))
struct TranscriptStoreFollowTests {
    private static let chunkSizes = [1, 17, 211, 1_024, 4_096, 333, 50, 2_900]

    @Test func appendedLinesBecomeAppendAndUpdateInLessThan300Milliseconds() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("lat"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "lat"), limit: 60)
        defer { subscription.cancel() }
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        let clock = ContinuousClock()

        let appendStart = clock.now
        try sandbox.append(line: SampleLines.user("novo prompt", uuid: "u-lat"), to: url)
        let appended = await recorder.wait { items, _, _ in items.contains { $0.id == "u-lat" } }
        let appendLatency = clock.now - appendStart

        try sandbox.append(line: SampleLines.toolUse(id: "toolu_lat", uuid: "a-lat"), to: url)
        let toolArrived = await recorder.wait { items, _, _ in items.contains { $0.id == "a-lat" } }
        let updateStart = clock.now
        try sandbox.append(line: SampleLines.toolResult(id: "toolu_lat", uuid: "r-lat"), to: url)
        let updated = await recorder.wait { items, _, _ in
            items.contains { item in
                if case .toolCall(let call) = item.kind { return call.toolUseId == "toolu_lat" && call.status == .succeeded }
                return false
            }
        }
        let updateLatency = clock.now - updateStart

        print("transcript: chatAppend em \(appendLatency), chatUpdate em \(updateLatency)")
        #expect(appended)
        #expect(toolArrived)
        #expect(updated)
        #expect(appendLatency < .milliseconds(300))
        #expect(updateLatency < .milliseconds(300))
        #expect(await recorder.updateCount == 1)
        #expect(await recorder.problems.isEmpty)
    }

    @Test(arguments: ["clear-and-compact", "tool-calls"])
    func chunkedWritesReachTheFullReadThroughDeltas(_ name: String) async throws {
        let bytes = try TranscriptFixtures.bytes(name)
        let document = try TranscriptFixtures.document(name)
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write([UInt8](), to: sandbox.sessionURL(name))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: name), limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page.items.isEmpty)
        let recorder = await TranscriptDeltaRecorder.start(subscription)

        var written = 0
        var step = 0
        var cutLines = 0
        while written < bytes.count {
            let end = min(bytes.count, written + Self.chunkSizes[step % Self.chunkSizes.count])
            try sandbox.append(bytes[written..<end], to: url)
            written = end
            step += 1
            if bytes[end - 1] != 0x0A { cutLines += 1 }
            let expected = TranscriptDocument(bytes: Array(bytes[..<end])).items
            let reached = await recorder.waitForItems(expected)
            #expect(reached, "\(name): lista diferente depois de \(end) bytes")
            if !reached { break }
        }
        #expect(cutLines > 0)
        #expect(await recorder.items == document.items)
        #expect(await recorder.problems.isEmpty)
        #expect(await recorder.meta.title == document.header.title)
        #expect(await recorder.meta.branch == document.header.branch)
        if name == "tool-calls" {
            #expect(await recorder.updateCount > 0)
        }
    }

    @Test func linesWrittenDuringOpenArriveExactlyOnce() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("atom"))
        let base = try TranscriptFixtures.document("basic-turn").items
        let once = OneShot()
        let path = url.path(percentEncoded: false)
        let hooks = TranscriptStoreHooks(afterPageRead: { _ in
            guard once.claim(), let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            let lines = SampleLines.user("durante o open", uuid: "u-open") + "\n"
                + SampleLines.assistantText("resposta", uuid: "a-open") + "\n"
            try? handle.write(contentsOf: Data(lines.utf8))
        })
        let store = TranscriptStore(projectsRoot: sandbox.rootPath, hooks: hooks)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "atom"), limit: 500)
        defer { subscription.cancel() }
        #expect(subscription.page.items == base)
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        #expect(await recorder.wait { items, _, _ in items.count == base.count + 2 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(await recorder.items.map(\.id).suffix(2) == ["u-open", "a-open"])
        #expect(await recorder.items.count == base.count + 2)
        #expect(await recorder.problems.isEmpty)
    }

    @Test func secondSubscriberGetsLinesWrittenDuringItsOpenOnceLikeTheFirst() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("dois"))
        let base = try TranscriptFixtures.document("basic-turn").items
        let opens = OneShot()
        let path = url.path(percentEncoded: false)
        let hooks = TranscriptStoreHooks(afterPageRead: { _ in
            if opens.claim() { return }
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((SampleLines.user("no segundo open", uuid: "u-second") + "\n").utf8))
        })
        let store = TranscriptStore(projectsRoot: sandbox.rootPath, hooks: hooks)
        let session = TranscriptSession(sessionId: "dois")
        let first = try await store.open(session: session, limit: 500)
        defer { first.cancel() }
        let firstRecorder = await TranscriptDeltaRecorder.start(first)
        let second = try await store.open(session: session, limit: 500)
        defer { second.cancel() }
        let secondRecorder = await TranscriptDeltaRecorder.start(second)
        #expect(second.page.items == base)
        #expect(await firstRecorder.wait { items, _, _ in items.count == base.count + 1 })
        #expect(await secondRecorder.wait { items, _, _ in items.count == base.count + 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(await firstRecorder.items == secondRecorder.items)
        #expect(await firstRecorder.items.last?.id == "u-second")
        #expect(await firstRecorder.problems.isEmpty)
        #expect(await secondRecorder.problems.isEmpty)
    }

    @Test func subscribersShareDeltasAndCancellingOneKeepsTheOther() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("par"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let session = TranscriptSession(sessionId: "par")
        let first = try await store.open(session: session, limit: 60)
        let second = try await store.open(session: session, limit: 60)
        defer { second.cancel() }
        let firstRecorder = await TranscriptDeltaRecorder.start(first)
        let secondRecorder = await TranscriptDeltaRecorder.start(second)
        #expect(await store.subscriberCount(forSession: "par") == 2)

        try sandbox.append(line: SampleLines.user("para os dois", uuid: "u-both"), to: url)
        #expect(await firstRecorder.wait { items, _, _ in items.last?.id == "u-both" })
        #expect(await secondRecorder.wait { items, _, _ in items.last?.id == "u-both" })
        #expect(await firstRecorder.deltas == secondRecorder.deltas)

        first.cancel()
        #expect(await firstRecorder.wait { _, _, finished in finished })
        #expect(await waitUntil { await store.subscriberCount(forSession: "par") == 1 })
        try sandbox.append(line: SampleLines.user("só o segundo", uuid: "u-second"), to: url)
        #expect(await secondRecorder.wait { items, _, _ in items.last?.id == "u-second" })
        #expect(await firstRecorder.items.last?.id == "u-both")
        #expect(await store.isFollowingFile(forSession: "par"))
    }

    @Test func endingTheConsumerTaskUnsubscribes() async throws {
        let sandbox = try TranscriptSandbox()
        try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("fim"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "fim"), limit: 60)
        let consumer = Task {
            for await _ in subscription.deltas {}
        }
        #expect(await store.subscriberCount(forSession: "fim") == 1)
        consumer.cancel()
        #expect(await waitUntil { await store.subscriberCount(forSession: "fim") == 0 })
        #expect(await store.isActive(forSession: "fim") == false)
        #expect(await store.isFollowingFile(forSession: "fim") == false)
    }

    @Test func missingFileWithHookPathIsEmptyUntilItAppears() async throws {
        let sandbox = try TranscriptSandbox()
        let url = sandbox.sessionURL("nova", project: "-Users-dev-projeto-novo")
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let session = TranscriptSession(sessionId: "nova", transcriptPath: url.path(percentEncoded: false))
        let subscription = try await store.open(session: session, limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page.items.isEmpty)
        #expect(!subscription.page.hasMore)
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        try sandbox.write(try TranscriptFixtures.bytes("clear-and-compact"), to: url)
        let expected = try TranscriptFixtures.document("clear-and-compact")
        #expect(await recorder.waitForItems(expected.items))
        #expect(await recorder.wait { _, meta, _ in meta.title == "Novo" })
        #expect(await store.isFollowingFile(forSession: "nova"))
    }

    @Test func missingFileWithoutHookPathIsFoundInAnExistingProject() async throws {
        let sandbox = try TranscriptSandbox()
        try FileManager.default.createDirectory(at: sandbox.projectURL(), withIntermediateDirectories: true)
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "sem-hook"), limit: 60)
        defer { subscription.cancel() }
        #expect(subscription.page.items.isEmpty)
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        let url = try sandbox.write(Array((SampleLines.user("primeira mensagem", uuid: "u-first") + "\n").utf8), to: sandbox.sessionURL("sem-hook"))
        #expect(await recorder.wait { items, _, _ in items.map(\.id) == ["u-first"] })
        try sandbox.append(line: SampleLines.assistantText("oi", uuid: "a-first"), to: url)
        #expect(await recorder.wait { items, _, _ in items.map(\.id) == ["u-first", "a-first"] })
    }

    @Test func missingFileWithoutHookPathIsFoundInANewProject() async throws {
        let sandbox = try TranscriptSandbox()
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "projeto-novo"), limit: 60)
        defer { subscription.cancel() }
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        let project = sandbox.projectURL("-Users-dev-recem-criado")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(100))
        try sandbox.write(Array((SampleLines.user("oi", uuid: "u-new") + "\n").utf8), to: sandbox.sessionURL("projeto-novo", project: "-Users-dev-recem-criado"))
        #expect(await recorder.wait { items, _, _ in items.map(\.id) == ["u-new"] })
    }

    @Test func switchingSessionsMovesTheFollowedFile() async throws {
        let sandbox = try TranscriptSandbox()
        let oldURL = try sandbox.write(try TranscriptFixtures.bytes("basic-turn"), to: sandbox.sessionURL("antiga"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let old = try await store.open(session: TranscriptSession(sessionId: "antiga"), limit: 60)
        let oldRecorder = await TranscriptDeltaRecorder.start(old)

        let newURL = try sandbox.write(try TranscriptFixtures.bytes("clear-and-compact"), to: sandbox.sessionURL("nova"))
        let current = try await store.open(session: TranscriptSession(sessionId: "nova"), limit: 60)
        defer { current.cancel() }
        let newRecorder = await TranscriptDeltaRecorder.start(current)
        old.cancel()
        #expect(await waitUntil { await !store.isActive(forSession: "antiga") })
        #expect(await store.isFollowingFile(forSession: "nova"))
        guard case .slashCommand(let firstCommand, _, _) = current.page.items.first?.kind, firstCommand == "/clear" else {
            Issue.record("a sessão nova deveria começar com /clear")
            return
        }

        try sandbox.append(line: SampleLines.user("metadado na antiga", uuid: "u-old"), to: oldURL)
        try sandbox.append(line: SampleLines.user("na nova", uuid: "u-new"), to: newURL)
        #expect(await newRecorder.wait { items, _, _ in items.last?.id == "u-new" })
        try await Task.sleep(for: .milliseconds(100))
        #expect(await oldRecorder.items.contains { $0.id == "u-old" } == false)
        #expect(await newRecorder.items.contains { $0.id == "u-old" } == false)
    }

    @Test func recreatedFileIsFollowedAgain() async throws {
        let sandbox = try TranscriptSandbox()
        let url = try sandbox.write(Array((SampleLines.user("antes", uuid: "u-before") + "\n").utf8), to: sandbox.sessionURL("recriada"))
        let store = TranscriptStore(projectsRoot: sandbox.rootPath)
        let subscription = try await store.open(session: TranscriptSession(sessionId: "recriada"), limit: 60)
        defer { subscription.cancel() }
        let recorder = await TranscriptDeltaRecorder.start(subscription)
        try FileManager.default.removeItem(at: url)
        #expect(await waitUntil { await !store.isFollowingFile(forSession: "recriada") })
        try sandbox.write(Array((SampleLines.user("depois", uuid: "u-after") + "\n").utf8), to: url)
        #expect(await recorder.wait { items, _, _ in items.map(\.id) == ["u-before", "u-after"] })
        #expect(await store.isFollowingFile(forSession: "recriada"))
    }
}
