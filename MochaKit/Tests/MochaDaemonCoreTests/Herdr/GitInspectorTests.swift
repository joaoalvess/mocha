import Foundation
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

final class HerdrTestInstantSource: Sendable {
    private let current = Mutex(ContinuousClock.now)

    var now: ContinuousClock.Instant {
        current.withLock { $0 }
    }

    func advance(by duration: Duration) {
        current.withLock { $0 = $0.advanced(by: duration) }
    }
}

@Suite struct GitInspectorTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "mocha-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func branchIsReadFromHeadWithoutSubprocess() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appending(path: "repo", directoryHint: .isDirectory)
        try write("ref: refs/heads/main\n", to: repo.appending(path: ".git/HEAD"))
        let nested = repo.appending(path: "Sources/App", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(GitHeadReader.branch(forDirectory: repo.path(percentEncoded: false)) == "main")
        #expect(GitHeadReader.branch(forDirectory: nested.path(percentEncoded: false)) == "main")
        try write("ref: refs/heads/feature/login\n", to: repo.appending(path: ".git/HEAD"))
        #expect(GitHeadReader.branch(forDirectory: repo.path(percentEncoded: false)) == "feature/login")
        try write("0123456789abcdef0123456789abcdef01234567\n", to: repo.appending(path: ".git/HEAD"))
        #expect(GitHeadReader.branch(forDirectory: repo.path(percentEncoded: false)) == "0123456")
    }

    @Test func linkedWorktreeFollowsTheGitdirPointer() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appending(path: "repo", directoryHint: .isDirectory)
        try write("ref: refs/heads/main\n", to: repo.appending(path: ".git/HEAD"))
        try write("ref: refs/heads/feature-x\n", to: repo.appending(path: ".git/worktrees/feature-x/HEAD"))
        let relative = root.appending(path: "relative-worktree", directoryHint: .isDirectory)
        try write("gitdir: ../repo/.git/worktrees/feature-x\n", to: relative.appending(path: ".git"))
        #expect(GitHeadReader.branch(forDirectory: relative.path(percentEncoded: false)) == "feature-x")
        let absolute = root.appending(path: "absolute-worktree", directoryHint: .isDirectory)
        let gitdir = repo.appending(path: ".git/worktrees/feature-x").path(percentEncoded: false)
        try write("gitdir: \(gitdir)\n", to: absolute.appending(path: ".git"))
        #expect(GitHeadReader.branch(forDirectory: absolute.path(percentEncoded: false)) == "feature-x")
    }

    @Test func directoryOutsideARepositoryHasNoBranch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GitHeadReader.branch(forDirectory: root.path(percentEncoded: false)) == nil)
        #expect(GitHeadReader.branch(forDirectory: "/nonexistent/mocha/path") == nil)
    }

    @Test func dirtyCheckRunsStatusWithoutOptionalLocks() async throws {
        let runner = FakeGitCommandRunner(result: GitCommandResult(exitCode: 0, output: Data(" M Sources/App.swift\n".utf8)))
        let inspector = GitInspector(runner: runner)
        #expect(await inspector.isDirty(at: "/Users/dev/projects/demo-app"))
        #expect(runner.calls == [[
            "--no-optional-locks", "-C", "/Users/dev/projects/demo-app", "status", "--porcelain=v1", "--untracked-files=normal",
        ]])
    }

    @Test func cleanOrFailingStatusIsNotDirty() async throws {
        let clean = GitInspector(runner: FakeGitCommandRunner(result: GitCommandResult(exitCode: 0, output: Data())))
        #expect(await clean.isDirty(at: "/a") == false)
        let failing = GitInspector(runner: FakeGitCommandRunner(result: GitCommandResult(exitCode: 128, output: Data("fatal".utf8))))
        #expect(await failing.isDirty(at: "/b") == false)
    }

    @Test func dirtyCheckIsCachedForFifteenSecondsPerDirectory() async throws {
        let clock = HerdrTestInstantSource()
        let runner = FakeGitCommandRunner(result: GitCommandResult(exitCode: 0, output: Data("?? new\n".utf8)))
        let inspector = GitInspector(runner: runner, now: { clock.now })
        #expect(await inspector.isDirty(at: "/repo"))
        runner.setResult(GitCommandResult(exitCode: 0, output: Data()))
        clock.advance(by: .seconds(14))
        #expect(await inspector.isDirty(at: "/repo"))
        #expect(runner.calls.count == 1)
        #expect(await inspector.isDirty(at: "/other") == false)
        #expect(runner.calls.count == 2)
        clock.advance(by: .seconds(2))
        #expect(await inspector.isDirty(at: "/repo") == false)
        #expect(runner.calls.count == 3)
    }

    @Test func invalidationForcesTheNextDirtyCheckOfThatDirectoryOnly() async throws {
        let clock = HerdrTestInstantSource()
        let runner = FakeGitCommandRunner(result: GitCommandResult(exitCode: 0, output: Data()))
        let inspector = GitInspector(runner: runner, now: { clock.now })
        #expect(await inspector.isDirty(at: "/repo") == false)
        #expect(await inspector.isDirty(at: "/other") == false)
        runner.setResult(GitCommandResult(exitCode: 0, output: Data("?? new\n".utf8)))
        clock.advance(by: .seconds(1))

        await inspector.invalidateDirty(at: "/repo")

        #expect(await inspector.isDirty(at: "/repo"))
        #expect(await inspector.isDirty(at: "/other") == false)
        #expect(await inspector.isDirty(at: "/repo"))
        #expect(runner.calls.count == 3)
    }

    @Test func aCheckStartedBeforeTheInvalidationDoesNotRefillTheCache() async throws {
        let runner = GatedGitRunner(outputs: ["", "?? new\n"])
        let inspector = GitInspector(runner: runner)
        let stale = Task { await inspector.isDirty(at: "/repo") }
        _ = try await eventually { await runner.callCount == 1 ? true : nil }

        await inspector.invalidateDirty(at: "/repo")
        let fresh = Task { await inspector.isDirty(at: "/repo") }
        _ = try await eventually { await runner.callCount == 2 ? true : nil }
        await runner.release()

        #expect(await stale.value == false)
        #expect(await fresh.value)
        #expect(await inspector.isDirty(at: "/repo"))
        #expect(await runner.callCount == 2)
    }

    @Test func systemRunnerCapturesOutputAndExitCode() async throws {
        let echo = SystemGitCommandRunner(executableURL: URL(filePath: "/bin/echo"))
        let result = try await echo.run(arguments: ["status"])
        #expect(result.exitCode == 0)
        #expect(String(decoding: result.output, as: UTF8.self) == "status\n")
        let failing = SystemGitCommandRunner(executableURL: URL(filePath: "/usr/bin/false"))
        #expect(try await failing.run(arguments: []).exitCode != 0)
        #expect(SystemGitCommandRunner().executableURL.path(percentEncoded: false) == "/usr/bin/git")
    }
}

actor GatedGitRunner: GitCommandRunning {
    private var outputs: [String]
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var callCount = 0

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func run(arguments: [String]) async throws -> GitCommandResult {
        callCount += 1
        let output = outputs.isEmpty ? "" : outputs.removeFirst()
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return GitCommandResult(exitCode: 0, output: Data(output.utf8))
    }

    func release() {
        isOpen = true
        for continuation in waiting {
            continuation.resume()
        }
        waiting.removeAll()
    }
}
