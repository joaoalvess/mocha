import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct TranscriptLocatorTests {
    private let sessionId = "0b7e4c2a-6f1d-4a8e-9c3b-5d2f1e8a7c64"

    @Test func resolvesOneLevelAndIgnoresNestedFiles() throws {
        let sandbox = try TranscriptSandbox()
        let project = sandbox.projectURL("-Users-dev-a")
        let line = Array((SampleLines.user("isca", uuid: "decoy") + "\n").utf8)
        try sandbox.write(line, to: project.appending(path: "\(sessionId)/subagents/agent-a1.jsonl"))
        try sandbox.write(line, to: project.appending(path: "\(sessionId)/subagents/\(sessionId).jsonl"))
        try sandbox.write(line, to: project.appending(path: "memory/\(sessionId).jsonl"))
        try sandbox.write(line, to: project.appending(path: "vercel-plugin/\(sessionId).jsonl"))
        try sandbox.write(Array("{\"skill\":\"x\"}\n".utf8), to: project.appending(path: "vercel-plugin/skill-injections.jsonl"))
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)
        #expect(locator.existingPath(forSessionId: sessionId) == nil)

        let real = try sandbox.write(line, to: sandbox.sessionURL(sessionId, project: "-Users-dev-b"))
        #expect(locator.existingPath(forSessionId: sessionId) == real.path(percentEncoded: false))
    }

    @Test func transcriptPathTakesPrecedenceEvenWhenMissing() throws {
        let sandbox = try TranscriptSandbox()
        try sandbox.write(Array("\n".utf8), to: sandbox.sessionURL(sessionId))
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)
        let hookPath = sandbox.root.appending(path: "outro/\(sessionId).jsonl").path(percentEncoded: false)
        #expect(locator.path(for: .init(sessionId: sessionId, transcriptPath: hookPath)) == hookPath)
        #expect(locator.path(for: .init(sessionId: sessionId)) == sandbox.sessionURL(sessionId).path(percentEncoded: false))
    }

    @Test func cachedPathIsDroppedWhenTheFileMoves() throws {
        let sandbox = try TranscriptSandbox()
        let first = try sandbox.write(Array("\n".utf8), to: sandbox.sessionURL(sessionId, project: "a"))
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)
        #expect(locator.existingPath(forSessionId: sessionId) == first.path(percentEncoded: false))
        let second = sandbox.sessionURL(sessionId, project: "b")
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: first, to: second)
        #expect(locator.existingPath(forSessionId: sessionId) == second.path(percentEncoded: false))
    }

    @Test func missingRootResolvesNothing() {
        let locator = TranscriptLocator(projectsRoot: "/tmp/mocha-sem-projetos-\(UUID().uuidString)")
        #expect(locator.existingPath(forSessionId: sessionId) == nil)
        #expect(locator.directoriesToWatch(for: .init(sessionId: sessionId)) == ["/tmp"] || locator.directoriesToWatch(for: .init(sessionId: sessionId)) == ["/private/tmp"])
    }

    @Test func cursorsRoundTripAndRejectGarbage() {
        let cursor = TranscriptCursor(sessionId: sessionId, offset: 120_394)
        #expect(cursor.text == "\(sessionId):120394")
        #expect(TranscriptCursor(cursor.text) == cursor)
        #expect(TranscriptCursor("sem-offset") == nil)
        #expect(TranscriptCursor(":10") == nil)
        #expect(TranscriptCursor("\(sessionId):-1") == nil)
        #expect(TranscriptCursor("\(sessionId):abc") == nil)
    }
}
