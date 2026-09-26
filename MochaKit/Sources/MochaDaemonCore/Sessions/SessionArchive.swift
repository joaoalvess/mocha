import Foundation
import MochaProtocol
import os

let sessionsLogger = Logger(subsystem: "com.joaoalves.mocha", category: "sessions")

public actor SessionArchive: SessionArchiving {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let maxSessions = 50

    public nonisolated let fileURL: URL
    private let clock: any GatewayClock
    private let broadcast: LatestValueBroadcast<[ArchivedSession]>
    private var contents: SessionArchiveContents

    public init(fileURL: URL, clock: any GatewayClock = SystemGatewayClock()) {
        self.fileURL = fileURL
        self.clock = clock
        let loaded = Self.load(fileURL) ?? SessionArchiveContents()
        let pruned = Self.pruned(loaded, now: clock.now())
        let current = pruned == loaded ? loaded : Self.persist(pruned, to: fileURL)
        contents = current
        broadcast = LatestValueBroadcast(current.sessions)
    }

    public nonisolated func events() -> AsyncStream<[ArchivedSession]> {
        broadcast.subscribe()
    }

    public var sessions: [ArchivedSession] {
        contents.sessions
    }

    public var userArchived: [String: Date] {
        contents.userArchived
    }

    public func session(_ sessionId: String) -> ArchivedSession? {
        contents.sessions.first { $0.id == sessionId }
    }

    public func sessionEnded(_ session: ArchivedSession) {
        var record = session
        record.endedAt = clock.now()
        update { contents in
            contents.sessions.removeAll { $0.id == record.id }
            contents.sessions.append(record)
        }
    }

    public func archive(sessionId: String, at date: Date) {
        update { $0.userArchived[sessionId] = date }
    }

    public func archivedAt(sessionId: String) -> Date? {
        contents.userArchived[sessionId]
    }

    public func turnStarted(sessionId: String, at date: Date) {
        guard let archivedAt = contents.userArchived[sessionId], archivedAt < date else { return }
        update { contents in
            guard let archivedAt = contents.userArchived[sessionId], archivedAt < date else { return }
            contents.userArchived[sessionId] = nil
        }
    }

    public func sessionResumed(sessionId: String) {
        guard contents.sessions.contains(where: { $0.id == sessionId }) else { return }
        update { $0.sessions.removeAll { $0.id == sessionId } }
    }

    private func update(_ change: (inout SessionArchiveContents) -> Void) {
        let base = Self.load(fileURL) ?? contents
        var updated = base
        change(&updated)
        updated = Self.pruned(updated, now: clock.now())
        let previous = contents.sessions
        contents = updated == base ? updated : Self.persist(updated, to: fileURL)
        if contents.sessions != previous {
            broadcast.publish(contents.sessions)
        }
    }

    static func pruned(_ contents: SessionArchiveContents, now: Date) -> SessionArchiveContents {
        let cutoff = now.addingTimeInterval(-retention)
        var seen: Set<String> = []
        let sessions = contents.sessions
            .filter { ($0.lastActivityAt ?? $0.endedAt) >= cutoff }
            .sorted(by: isMoreRecent)
            .filter { seen.insert($0.id).inserted }
            .prefix(maxSessions)
        return SessionArchiveContents(
            sessions: Array(sessions),
            userArchived: contents.userArchived.filter { $0.value >= cutoff }
        )
    }

    private static func isMoreRecent(_ lhs: ArchivedSession, _ rhs: ArchivedSession) -> Bool {
        let left = lhs.lastActivityAt ?? lhs.endedAt
        let right = rhs.lastActivityAt ?? rhs.endedAt
        if left != right {
            return left > right
        }
        if lhs.endedAt != rhs.endedAt {
            return lhs.endedAt > rhs.endedAt
        }
        return lhs.id < rhs.id
    }

    private static func load(_ url: URL) -> SessionArchiveContents? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SessionArchiveContents.self, from: data)
        } catch {
            sessionsLogger.error("sessions.json is invalid; keeping the sessions in memory")
            return nil
        }
    }

    private static func persist(_ contents: SessionArchiveContents, to url: URL) -> SessionArchiveContents {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(contents)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try AtomicFile.write(data, to: url, permissions: 0o600)
            return (try? JSONDecoder().decode(SessionArchiveContents.self, from: data)) ?? contents
        } catch {
            sessionsLogger.error("failed to write sessions.json: \(String(describing: error), privacy: .public)")
            return contents
        }
    }
}

public struct SessionArchiveContents: Codable, Sendable, Equatable {
    public var sessions: [ArchivedSession]
    public var userArchived: [String: Date]

    public init(sessions: [ArchivedSession] = [], userArchived: [String: Date] = [:]) {
        self.sessions = sessions
        self.userArchived = userArchived
    }

    private enum CodingKeys: String, CodingKey {
        case sessions, userArchived
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([LossySession].self, forKey: .sessions) ?? []
        sessions = entries.compactMap(\.session)
        let stamps = try container.decodeIfPresent([String: String].self, forKey: .userArchived) ?? [:]
        userArchived = stamps.compactMapValues(ProtocolDate.date(from:))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(userArchived.mapValues(ProtocolDate.string(from:)), forKey: .userArchived)
    }

    private struct LossySession: Decodable {
        let session: ArchivedSession?

        init(from decoder: any Decoder) {
            session = try? ArchivedSession(from: decoder)
        }
    }
}
