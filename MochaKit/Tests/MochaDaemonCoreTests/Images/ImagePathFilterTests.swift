import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct ImagePathFilterTests {
    private struct Files {
        let directory: URL
        let existing: String
        let missing: String
        let folder: String
        let link: String
        let linkToFolder: String
        let behindClosedFolder: String
        let closedFolder: URL

        static func make() throws -> Files {
            let directory = try TestImages.directory()
            let existing = directory.appending(path: "existe.png")
            try Data([1, 2, 3]).write(to: existing)
            let folder = directory.appending(path: "pasta.png", directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let link = directory.appending(path: "atalho.png")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existing)
            let linkToFolder = directory.appending(path: "atalho-pasta.png")
            try FileManager.default.createSymbolicLink(at: linkToFolder, withDestinationURL: folder)
            let closedFolder = directory.appending(path: "fechada", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: closedFolder, withIntermediateDirectories: true)
            let behindClosedFolder = closedFolder.appending(path: "dentro.png")
            try Data([1]).write(to: behindClosedFolder)
            try TestImages.setPermissions(0o000, of: closedFolder)
            return Files(
                directory: directory,
                existing: existing.fileSystemPath,
                missing: directory.appending(path: "sumiu.png").fileSystemPath,
                folder: folder.fileSystemPath,
                link: link.fileSystemPath,
                linkToFolder: linkToFolder.fileSystemPath,
                behindClosedFolder: behindClosedFolder.fileSystemPath,
                closedFolder: closedFolder
            )
        }

        var all: [String] {
            [missing, existing, folder, behindClosedFolder, link, linkToFolder]
        }

        var kept: [String] {
            [existing, link]
        }

        func remove() {
            try? TestImages.setPermissions(0o700, of: closedFolder)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func withFiles(_ body: (Files) async throws -> Void) async throws {
        let files = try Files.make()
        defer { files.remove() }
        try await body(files)
    }

    @Test func onlyRegularFilesStay() async throws {
        try await withFiles { files in
            #expect(ImageFiles.existing(files.all) == files.kept)
            #expect(ImageFiles.isRegularFile(atPath: files.existing))
            #expect(ImageFiles.isRegularFile(atPath: files.missing) == false)
            #expect(ImageFiles.isRegularFile(atPath: files.folder) == false)
            #expect(ImageFiles.isRegularFile(atPath: files.behindClosedFolder) == false)
        }
    }

    @Test func overlaidFiltersEveryKindOfItem() async throws {
        try await withFiles { files in
            try await withHub { harness in
                let text = ChatItem(id: "t", at: Sample.start, kind: .assistantText(markdown: "x"), imagePaths: files.all)
                #expect(await harness.hub.overlaid(text).imagePaths == files.kept)
                #expect(await harness.hub.overlaid(text).kind == text.kind)

                let call = ToolCall(toolUseId: "r1", name: "Read", summary: "existe.png", inputJSON: "{}", status: .succeeded)
                let read = ChatItem(id: "r", at: Sample.start, kind: .toolCall(call), imagePaths: [files.missing])
                #expect(await harness.hub.overlaid(read).imagePaths.isEmpty)

                let prompt = ChatItem(id: "p", at: Sample.start, kind: .userPrompt(text: "", imageCount: 2), imagePaths: [files.existing, files.missing])
                let filtered = await harness.hub.overlaid(prompt)
                #expect(filtered.imagePaths == [files.existing])
                #expect(filtered.kind == .userPrompt(text: "", imageCount: 2))

                let card = ChatItem(
                    id: "s",
                    at: Sample.start,
                    kind: .subagent(SubagentCall(toolUseId: "a1", agentType: "Explore", description: "d", status: .running)),
                    imagePaths: [files.folder, files.existing]
                )
                #expect(await harness.hub.overlaid(card).imagePaths == [files.existing])

                let plain = Sample.item("i", text: "sem imagens")
                #expect(await harness.hub.overlaid(plain) == plain)
            }
        }
    }

    @Test func chatPagesAppendsAndUpdatesCarryOnlyExistingPaths() async throws {
        try await withFiles { files in
            let item = ChatItem(id: "i1", at: Sample.start, kind: .assistantText(markdown: "veja"), imagePaths: files.all)
            try await withHub(configure: { transcripts in
                await transcripts.setPage(Sample.page([item]), forSession: Sample.sessionA)
            }) { harness in
                let (socket, _) = try await harness.pairedClient()
                let reply = try await socket.reply(to: .openChat(target: .agent("w1:p1")))
                guard case .chatPage(let page) = reply else { throw UnexpectedMessage(message: reply) }
                #expect(page.items.map(\.imagePaths) == [files.kept])

                let appended = ChatItem(id: "i2", at: Sample.start, kind: .assistantText(markdown: "mais"), imagePaths: [files.missing, files.existing])
                await harness.transcripts.emit(.append([appended]), toSession: Sample.sessionA)
                guard case .chatAppend(_, let appendedItems) = try await socket.nextMessage() else {
                    Issue.record("esperava chatAppend")
                    return
                }
                #expect(appendedItems.map(\.imagePaths) == [[files.existing]])

                let call = ToolCall(toolUseId: "r1", name: "Read", summary: "x", inputJSON: "{}", status: .succeeded)
                let updated = ChatItem(id: "i3", at: Sample.start, kind: .toolCall(call), imagePaths: [files.folder])
                await harness.transcripts.emit(.update([updated]), toSession: Sample.sessionA)
                guard case .chatUpdate(_, let updatedItems) = try await socket.nextMessage() else {
                    Issue.record("esperava chatUpdate")
                    return
                }
                #expect(updatedItems.map(\.imagePaths) == [[]])
            }
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ImageDecodeLimiterTests {
    @Test func atMostTwoDecodesRunAtOnce() async throws {
        let limiter = ImageDecodeLimiter()
        #expect(ImageDecodeLimiter.defaultLimit == 2)
        await limiter.acquire()
        await limiter.acquire()
        #expect(await limiter.activeCount == 2)

        let third = Task {
            await limiter.acquire()
        }
        #expect(try await eventually { await limiter.waitingCount == 1 ? true : nil })
        #expect(await limiter.activeCount == 2)

        await limiter.release()
        await third.value
        #expect(await limiter.waitingCount == 0)
        #expect(await limiter.activeCount == 2)

        await limiter.release()
        await limiter.release()
        #expect(await limiter.activeCount == 0)
    }
}
