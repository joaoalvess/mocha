import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore

@Suite struct TranscriptStoreSubagentTests {
    private func subagentSession(_ projects: SubagentProjects, agentId: String) async throws -> TranscriptSession {
        let resolver = SubagentStore(projectsRoot: projects.rootPath)
        let transcript = try #require(await resolver.transcript(session: SubagentProjects.backgroundSession, agentId: agentId))
        return TranscriptSession(sessionId: SubagentProjects.backgroundSession, subagent: transcript)
    }

    @Test func forkOpensAtTheBoundaryWithTheTaskOnTop() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "subagents-background", session: SubagentProjects.backgroundSession)
        let session = try await subagentSession(projects, agentId: "a4444444444444444")
        let store = TranscriptStore(projectsRoot: projects.rootPath)

        let subscription = try await store.open(session: session, limit: 200)
        defer { subscription.cancel() }
        guard case .task(let text) = subscription.page.items.first?.kind else {
            Issue.record("first item is not the task: \(String(describing: subscription.page.items.first))")
            return
        }
        #expect(!text.isEmpty)
        #expect(!subscription.page.items.contains { if case .turnFooter = $0.kind { true } else { false } })
    }

    @Test func pagesUseTheSubagentCursor() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "subagents-background", session: SubagentProjects.backgroundSession)
        let session = try await subagentSession(projects, agentId: "a1111111111111111")
        let store = TranscriptStore(projectsRoot: projects.rootPath)

        let subscription = try await store.open(session: session, limit: 1)
        defer { subscription.cancel() }
        let cursor = try #require(subscription.page.before)
        #expect(cursor.hasPrefix("\(SubagentProjects.backgroundSession)/a1111111111111111:"))
        let older = try await store.page(session: session, before: cursor, limit: 200)
        #expect(!older.items.isEmpty)

        let offset = cursor.split(separator: ":").last.map(String.init) ?? "0"
        await #expect(throws: TranscriptError.invalidCursor) {
            try await store.page(session: session, before: "\(SubagentProjects.backgroundSession):\(offset)", limit: 10)
        }
        let main = TranscriptSession(sessionId: SubagentProjects.backgroundSession)
        await #expect(throws: TranscriptError.invalidCursor) {
            try await store.page(session: main, before: cursor, limit: 10)
        }
    }

    @Test func metaOfTheSubagentComesFromItsOwnFile() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "subagents-background", session: SubagentProjects.backgroundSession)
        let session = try await subagentSession(projects, agentId: "a2222222222222222")
        let store = TranscriptStore(projectsRoot: projects.rootPath)
        let meta = try #require(await store.meta(forSession: session))
        #expect(meta.model == "claude-opus-5-5")
    }
}
