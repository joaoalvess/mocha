import Foundation
import MochaProtocol

public protocol SessionArchiving: Sendable {
    func events() -> AsyncStream<[ArchivedSession]>
    var sessions: [ArchivedSession] { get async }
    func session(_ sessionId: String) async -> ArchivedSession?
    func sessionEnded(_ session: ArchivedSession) async
    func archive(sessionId: String, at date: Date) async
    func archivedAt(sessionId: String) async -> Date?
    func turnStarted(sessionId: String, at date: Date) async
    func sessionResumed(sessionId: String) async
}
