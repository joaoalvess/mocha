import Foundation
import MochaProtocol

enum CodexAlert: Sendable, Equatable {
    case turnDone(AgentID, lastMessage: String?)
    case needsInput(PendingRequest)
    case needsInputWithoutActions(AgentID, body: String)
    case blocked(AgentID)
}

protocol CodexServing: Actor {
    nonisolated var updates: AsyncStream<CodexServiceUpdate> { get }
    nonisolated var socketPath: String { get }
    func expectPane(_ paneId: AgentID, cwd: String, since: Date)
    func retainPanes(_ paneIds: Set<AgentID>)
    func movePane(from oldId: AgentID, to newId: AgentID)
    func threadId(for paneId: AgentID) -> String?
    func page(threadId: String, before: String?, limit: Int) async throws -> CodexThreadPage
    func prompt(_ agent: HerdrAgent, text: String) async throws
    func interrupt(_ agent: HerdrAgent) async throws
    func respond(to requestId: RequestID, with response: PendingResponse) async throws
}
