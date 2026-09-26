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

    private func expectIgnored(_ hookPath: String, by locator: TranscriptLocator, sourceLocation: SourceLocation = #_sourceLocation) {
        let hooked = TranscriptSession(sessionId: sessionId, transcriptPath: hookPath)
        let plain = TranscriptSession(sessionId: sessionId)
        #expect(locator.trustedTranscriptPath(of: hooked) == nil, sourceLocation: sourceLocation)
        #expect(locator.path(for: hooked) == locator.path(for: plain), sourceLocation: sourceLocation)
        #expect(locator.directoriesToWatch(for: hooked) == locator.directoriesToWatch(for: plain), sourceLocation: sourceLocation)
    }

    private func searchable(_ sandbox: TranscriptSandbox) throws -> String {
        try sandbox.write(Array("\n".utf8), to: sandbox.sessionURL(sessionId, project: "-Users-dev-busca")).path(percentEncoded: false)
    }

    @Test func transcriptPathInsideTheRootIsUsedWhetherTheFileExistsOrNot() throws {
        let sandbox = try TranscriptSandbox()
        let found = try searchable(sandbox)
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)

        let existing = try sandbox.write(Array("\n".utf8), to: sandbox.sessionURL(sessionId, project: "-Users-dev-hook")).path(percentEncoded: false)
        let existingSession = TranscriptSession(sessionId: sessionId, transcriptPath: existing)
        #expect(locator.path(for: existingSession) == existing)
        #expect(locator.path(for: existingSession) != found)
        #expect(locator.directoriesToWatch(for: existingSession) == [(existing as NSString).deletingLastPathComponent])

        let missing = sandbox.sessionURL(sessionId, project: "-Users-dev-novo").path(percentEncoded: false)
        let missingSession = TranscriptSession(sessionId: sessionId, transcriptPath: missing)
        #expect(locator.path(for: missingSession) == missing)
        let project = (missing as NSString).deletingLastPathComponent
        #expect(locator.directoriesToWatch(for: missingSession) == [(project as NSString).deletingLastPathComponent])

        let insideWithDots = sandbox.rootPath + "-Users-dev-a/./../-Users-dev-hook/\(sessionId).jsonl"
        #expect(locator.path(for: .init(sessionId: sessionId, transcriptPath: insideWithDots)) == existing)
    }

    @Test func transcriptPathOutsideTheRootIsIgnored() throws {
        let sandbox = try TranscriptSandbox()
        let outside = try TranscriptSandbox()
        _ = try searchable(sandbox)
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)

        let existing = try outside.write(Array((SampleLines.user("segredo", uuid: "u-fora") + "\n").utf8), to: outside.sessionURL(sessionId))
        expectIgnored(existing.path(percentEncoded: false), by: locator)
        expectIgnored(outside.sessionURL(sessionId, project: "-Users-dev-novo").path(percentEncoded: false), by: locator)
        expectIgnored("/etc/\(sessionId).jsonl", by: locator)
        expectIgnored("-Users-dev-busca/\(sessionId).jsonl", by: locator)
    }

    @Test func dotDotLeavingTheRootIsIgnored() throws {
        let sandbox = try TranscriptSandbox()
        let outside = try TranscriptSandbox()
        _ = try searchable(sandbox)
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)
        try outside.write(Array("\n".utf8), to: outside.sessionURL(sessionId))

        let escaping = sandbox.rootPath + "-Users-dev-busca/../../\(outside.root.lastPathComponent)/-Users-dev-projects-demo-app/\(sessionId).jsonl"
        expectIgnored(escaping, by: locator)
        expectIgnored(sandbox.rootPath + "../\(sessionId).jsonl", by: locator)
    }

    @Test func symlinkInsideTheRootPointingOutsideIsIgnored() throws {
        let sandbox = try TranscriptSandbox()
        let outside = try TranscriptSandbox()
        _ = try searchable(sandbox)
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)
        let target = try outside.write(Array((SampleLines.user("segredo", uuid: "u-fora") + "\n").utf8), to: outside.sessionURL("qualquer"))
        let fileManager = FileManager.default

        let linkedDirectory = sandbox.root.appending(path: "-Users-dev-link")
        try fileManager.createSymbolicLink(at: linkedDirectory, withDestinationURL: target.deletingLastPathComponent())
        try outside.write(Array("\n".utf8), to: outside.sessionURL(sessionId))
        expectIgnored(linkedDirectory.appending(path: "\(sessionId).jsonl").path(percentEncoded: false), by: locator)
        expectIgnored(linkedDirectory.appending(path: "novo/\(sessionId).jsonl").path(percentEncoded: false), by: locator)

        let nested = sandbox.projectURL("-Users-dev-hook").appending(path: "aninhado", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        let linkedFile = nested.appending(path: "\(sessionId).jsonl")
        try fileManager.createSymbolicLink(at: linkedFile, withDestinationURL: target)
        expectIgnored(linkedFile.path(percentEncoded: false), by: locator)

        try fileManager.removeItem(at: linkedFile)
        try fileManager.createSymbolicLink(at: linkedFile, withDestinationURL: outside.root.appending(path: "ainda-nao-existe.jsonl"))
        expectIgnored(linkedFile.path(percentEncoded: false), by: locator)
    }

    @Test func transcriptPathNotNamedAfterTheSessionIsIgnored() throws {
        let sandbox = try TranscriptSandbox()
        _ = try searchable(sandbox)
        let locator = TranscriptLocator(projectsRoot: sandbox.rootPath)
        let other = try sandbox.write(Array("\n".utf8), to: sandbox.sessionURL("5c1e9a7b-4d2f-4b8a-9e3c-6f0a2d8b1c47", project: "-Users-dev-hook"))
        expectIgnored(other.path(percentEncoded: false), by: locator)
        expectIgnored(sandbox.projectURL("-Users-dev-hook").appending(path: "\(sessionId).json").path(percentEncoded: false), by: locator)
        expectIgnored(sandbox.projectURL("-Users-dev-hook").appending(path: "memory/MEMORY.md").path(percentEncoded: false), by: locator)
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
