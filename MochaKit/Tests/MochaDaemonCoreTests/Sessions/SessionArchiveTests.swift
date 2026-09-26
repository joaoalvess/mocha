import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct SessionArchiveTests {
    static let day: TimeInterval = 24 * 60 * 60

    static func record(
        _ id: String,
        title: String = "Paginação do chat",
        lastActivityAt: Date? = nil,
        endedAt: Date = Sample.start,
        reason: ArchiveReason = .cleared
    ) -> ArchivedSession {
        ArchivedSession(
            id: id,
            agentId: "w1:p1",
            title: title,
            workspaceLabel: "Core",
            model: "claude-opus-5-5",
            preview: MessagePreview(author: .assistant, text: "Pronto."),
            contextLeftPercent: 64,
            reason: reason,
            endedAt: endedAt,
            sessionStartedAt: Sample.start.addingTimeInterval(-3600),
            lastActivityAt: lastActivityAt
        )
    }

    static func withArchive(
        existing: String? = nil,
        _ body: (URL, ManualClock) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-sessions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "sessions.json")
        if let existing {
            try Data(existing.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
        }
        try await body(file, ManualClock(origin: Sample.start))
    }

    static func stored(_ file: URL) throws -> SessionArchiveContents {
        try JSONDecoder().decode(SessionArchiveContents.self, from: Data(contentsOf: file))
    }

    static func json(_ contents: SessionArchiveContents) throws -> String {
        String(decoding: try JSONEncoder().encode(contents), as: UTF8.self)
    }

    @Test func sessionEndedIsWrittenAtomicallyWith0600() async throws {
        try await Self.withArchive(existing: #"{"sessions": [], "userArchived": {}}"#) { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            #expect(fileMode(file) == 0o644)
            let firstInode = try #require(inode(file))

            clock.advance(by: .seconds(30))
            await archive.sessionEnded(Self.record(Sample.sessionA, lastActivityAt: Sample.start))
            #expect(fileMode(file) == 0o600)
            let secondInode = try #require(inode(file))
            #expect(secondInode != firstInode)

            let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            #expect(Set(object.keys) == ["sessions", "userArchived"])
            let sessions = try #require(object["sessions"] as? [[String: Any]])
            #expect(sessions.count == 1)
            #expect(sessions[0]["id"] as? String == Sample.sessionA)
            #expect(sessions[0]["reason"] as? String == "cleared")
            #expect(sessions[0]["endedAt"] as? String == ProtocolDate.string(from: Sample.start.addingTimeInterval(30)))

            await archive.archive(sessionId: Sample.sessionB, at: clock.now())
            #expect(inode(file) != secondInode)
            #expect(fileMode(file) == 0o600)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path(percentEncoded: false))
            #expect(leftovers == ["sessions.json"])
        }
    }

    @Test func sessionEndedReplacesTheSameSessionAndStampsEndedAt() async throws {
        try await Self.withArchive { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) == false)
            await archive.sessionEnded(Self.record(Sample.sessionA, title: "primeiro", endedAt: .distantPast))
            clock.advance(by: .seconds(60))
            await archive.sessionEnded(Self.record(Sample.sessionA, title: "segundo", reason: .ended))
            let sessions = await archive.sessions
            #expect(sessions.count == 1)
            #expect(sessions.first?.title == "segundo")
            #expect(sessions.first?.reason == .ended)
            #expect(sessions.first?.endedAt == Sample.start.addingTimeInterval(60))
            #expect(await archive.session(Sample.sessionA)?.title == "segundo")
            #expect(await archive.session(Sample.sessionB) == nil)
            #expect(try Self.stored(file).sessions == sessions)
        }
    }

    @Test func retentionKeepsSevenDaysAndFiftySessionsMostRecentFirst() async throws {
        var sessions = [
            Self.record("old", lastActivityAt: Sample.start.addingTimeInterval(-8 * Self.day), endedAt: Sample.start.addingTimeInterval(-Self.day)),
            Self.record("ended-six-days-ago", endedAt: Sample.start.addingTimeInterval(-6 * Self.day)),
            Self.record("active-five-days-ago", lastActivityAt: Sample.start.addingTimeInterval(-5 * Self.day)),
        ]
        for index in 0..<55 {
            sessions.append(Self.record(String(format: "recent-%02d", index), lastActivityAt: Sample.start.addingTimeInterval(-Double(index) * 60)))
        }
        let existing = try Self.json(SessionArchiveContents(
            sessions: sessions.shuffled(),
            userArchived: [
                "fresh": Sample.start.addingTimeInterval(-Self.day),
                "stale": Sample.start.addingTimeInterval(-8 * Self.day),
            ]
        ))
        try await Self.withArchive(existing: existing) { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            let kept = await archive.sessions
            #expect(kept.count == SessionArchive.maxSessions)
            #expect(kept.map(\.id) == (0..<50).map { String(format: "recent-%02d", $0) })
            #expect(await archive.userArchived.keys.sorted() == ["fresh"])
            #expect(try Self.stored(file).sessions.map(\.id) == kept.map(\.id))
            #expect(fileMode(file) == 0o600)
        }

        let few = try Self.json(SessionArchiveContents(sessions: [
            Self.record("old", lastActivityAt: Sample.start.addingTimeInterval(-8 * Self.day)),
            Self.record("ended-six-days-ago", endedAt: Sample.start.addingTimeInterval(-6 * Self.day)),
            Self.record("active-five-days-ago", lastActivityAt: Sample.start.addingTimeInterval(-5 * Self.day), endedAt: Sample.start),
        ]))
        try await Self.withArchive(existing: few) { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            #expect(await archive.sessions.map(\.id) == ["active-five-days-ago", "ended-six-days-ago"])
            clock.advance(by: .seconds(Int64(1.5 * Self.day)))
            await archive.sessionEnded(Self.record(Sample.sessionA, lastActivityAt: clock.now()))
            #expect(await archive.sessions.map(\.id) == [Sample.sessionA, "active-five-days-ago"])
            #expect(try Self.stored(file).sessions.map(\.id) == [Sample.sessionA, "active-five-days-ago"])
        }
    }

    @Test func userArchiveLastsUntilALaterTurn() async throws {
        try await Self.withArchive { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            let archivedAt = clock.now()
            await archive.archive(sessionId: Sample.sessionA, at: archivedAt)
            #expect(await archive.archivedAt(sessionId: Sample.sessionA) == archivedAt)
            #expect(await archive.archivedAt(sessionId: Sample.sessionB) == nil)
            #expect(try Self.stored(file).userArchived == [Sample.sessionA: archivedAt])

            await archive.turnStarted(sessionId: Sample.sessionA, at: archivedAt.addingTimeInterval(-60))
            #expect(await archive.archivedAt(sessionId: Sample.sessionA) == archivedAt)
            #expect(await SessionArchive(fileURL: file, clock: clock).archivedAt(sessionId: Sample.sessionA) == archivedAt)

            await archive.turnStarted(sessionId: Sample.sessionA, at: archivedAt.addingTimeInterval(60))
            #expect(await archive.archivedAt(sessionId: Sample.sessionA) == nil)
            #expect(try Self.stored(file).userArchived.isEmpty)
        }
    }

    @Test func resumedSessionLeavesTheList() async throws {
        try await Self.withArchive { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            var events = archive.events().makeAsyncIterator()
            #expect(await events.next() == [])

            await archive.sessionEnded(Self.record(Sample.sessionA, lastActivityAt: clock.now()))
            #expect(await events.next()?.map(\.id) == [Sample.sessionA])
            clock.advance(by: .seconds(10))
            await archive.sessionEnded(Self.record(Sample.sessionB, lastActivityAt: clock.now()))
            #expect(await events.next()?.map(\.id) == [Sample.sessionB, Sample.sessionA])

            await archive.sessionResumed(sessionId: Sample.sessionA)
            #expect(await events.next()?.map(\.id) == [Sample.sessionB])
            #expect(try Self.stored(file).sessions.map(\.id) == [Sample.sessionB])

            await archive.sessionResumed(sessionId: Sample.sessionC)
            clock.advance(by: .seconds(10))
            await archive.sessionEnded(Self.record(Sample.sessionC, lastActivityAt: clock.now()))
            #expect(await events.next()?.map(\.id) == [Sample.sessionC, Sample.sessionB])
        }
    }

    @Test func fileIsReadAgainBeforeEachWrite() async throws {
        try await Self.withArchive { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            await archive.sessionEnded(Self.record(Sample.sessionA, lastActivityAt: clock.now()))
            var external = try Self.stored(file)
            external.sessions.append(Self.record(Sample.sessionC, lastActivityAt: clock.now().addingTimeInterval(-120)))
            external.userArchived["outro"] = clock.now()
            try Data(try Self.json(external).utf8).write(to: file)

            clock.advance(by: .seconds(5))
            await archive.sessionEnded(Self.record(Sample.sessionB, lastActivityAt: clock.now()))
            let stored = try Self.stored(file)
            #expect(stored.sessions.map(\.id) == [Sample.sessionB, Sample.sessionA, Sample.sessionC])
            #expect(stored.userArchived.keys.sorted() == ["outro"])
            #expect(await archive.sessions.map(\.id) == [Sample.sessionB, Sample.sessionA, Sample.sessionC])
        }
    }

    @Test func invalidEntriesAreSkippedAndAnInvalidFileStartsEmpty() async throws {
        let valid = try Self.json(SessionArchiveContents(sessions: [Self.record(Sample.sessionA, lastActivityAt: Sample.start)]))
        let mixed = valid.replacingOccurrences(of: #""sessions":["#, with: #""sessions":[{"id":"sem-titulo"},"#)
        #expect(mixed != valid)
        try await Self.withArchive(existing: mixed) { file, clock async throws in
            #expect(await SessionArchive(fileURL: file, clock: clock).sessions.map(\.id) == [Sample.sessionA])
        }
        try await Self.withArchive(existing: "lixo") { file, clock async throws in
            let archive = SessionArchive(fileURL: file, clock: clock)
            #expect(await archive.sessions.isEmpty)
            await archive.sessionEnded(Self.record(Sample.sessionB, lastActivityAt: clock.now()))
            #expect(try Self.stored(file).sessions.map(\.id) == [Sample.sessionB])
        }
    }
}
