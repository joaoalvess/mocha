import Foundation

public protocol GitInspecting: Sendable {
    func branch(at directory: String) async -> String?
    func isDirty(at directory: String) async -> Bool
}

public struct GitCommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var output: Data

    public init(exitCode: Int32, output: Data) {
        self.exitCode = exitCode
        self.output = output
    }
}

public protocol GitCommandRunning: Sendable {
    func run(arguments: [String]) async throws -> GitCommandResult
}

public struct SystemGitCommandRunner: GitCommandRunning {
    public let executableURL: URL

    public init(executableURL: URL = URL(filePath: "/usr/bin/git")) {
        self.executableURL = executableURL
    }

    public func run(arguments: [String]) async throws -> GitCommandResult {
        let executableURL = self.executableURL
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: GitCommandResult(exitCode: process.terminationStatus, output: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public actor GitInspector: GitInspecting {
    public static let defaultDirtyCacheLifetime: Duration = .seconds(15)

    private struct CachedDirty {
        let value: Bool
        let checkedAt: ContinuousClock.Instant
    }

    private let runner: any GitCommandRunning
    private let dirtyCacheLifetime: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private var dirtyCache: [String: CachedDirty] = [:]
    private var dirtyChecks: [String: Task<Bool, Never>] = [:]

    public init(
        runner: any GitCommandRunning = SystemGitCommandRunner(),
        dirtyCacheLifetime: Duration = GitInspector.defaultDirtyCacheLifetime,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.runner = runner
        self.dirtyCacheLifetime = dirtyCacheLifetime
        self.now = now
    }

    public static func statusArguments(directory: String) -> [String] {
        ["--no-optional-locks", "-C", directory, "status", "--porcelain=v1", "--untracked-files=normal"]
    }

    public nonisolated func branch(at directory: String) async -> String? {
        GitHeadReader.branch(forDirectory: directory)
    }

    public func isDirty(at directory: String) async -> Bool {
        if let cached = dirtyCache[directory], cached.checkedAt.duration(to: now()) < dirtyCacheLifetime {
            return cached.value
        }
        if let running = dirtyChecks[directory] {
            return await running.value
        }
        let runner = self.runner
        let check = Task {
            guard let result = try? await runner.run(arguments: Self.statusArguments(directory: directory)) else { return false }
            return result.exitCode == 0 && !result.output.isEmpty
        }
        dirtyChecks[directory] = check
        let value = await check.value
        dirtyChecks[directory] = nil
        dirtyCache[directory] = CachedDirty(value: value, checkedAt: now())
        return value
    }
}

public enum GitHeadReader {
    public static func branch(forDirectory directory: String) -> String? {
        guard let gitDirectory = gitDirectory(containing: URL(filePath: directory, directoryHint: .isDirectory)),
            let head = try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8)
        else { return nil }
        return branch(fromHead: head)
    }

    static func branch(fromHead head: String) -> String? {
        let content = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        let refPrefix = "ref:"
        guard content.hasPrefix(refPrefix) else {
            return String(content.prefix(7))
        }
        let reference = content.dropFirst(refPrefix.count).trimmingCharacters(in: .whitespaces)
        let headsPrefix = "refs/heads/"
        return reference.hasPrefix(headsPrefix) ? String(reference.dropFirst(headsPrefix.count)) : reference
    }

    private static func gitDirectory(containing directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let dotGit = current.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isDirectory) {
                return isDirectory.boolValue ? dotGit : linkedGitDirectory(pointer: dotGit, base: current)
            }
            let path = current.path(percentEncoded: false)
            guard path != "/", !path.isEmpty else { return nil }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    private static func linkedGitDirectory(pointer: URL, base: URL) -> URL? {
        guard let content = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        let prefix = "gitdir:"
        guard let line = content.split(whereSeparator: \.isNewline).first.map(String.init), line.hasPrefix(prefix) else {
            return nil
        }
        let path = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return base.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
    }
}
