import Foundation
import os

let codexLogger = Logger(subsystem: "com.joaoalves.mocha", category: "codex")

public enum CodexExecutable {
    public static let lastValidatedVersion = "0.159.2"

    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appending(path: ".local/bin/codex").path(percentEncoded: false),
        ]
    }

    public static func resolve(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        candidates(home: home).first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

public struct CodexInspector: Sendable {
    public let executable: String?
    let runner: any ProcessRunning

    public init(executable: String?, runner: any ProcessRunning = SystemProcessRunner()) {
        self.executable = executable
        self.runner = runner
    }

    public func version() async -> String? {
        guard let executable,
              let output = try? await runner.run(executable, ["--version"], timeout: .seconds(5)),
              output.succeeded else { return nil }
        return output.outputText.split(separator: " ").last.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum CodexStaleServers {
    static let listArguments = ["-axww", "-o", "pid=,command="]

    static func pids(inProcessList output: String, socketPath: String) -> [pid_t] {
        let suffix = "app-server --listen unix://\(socketPath)"
        return output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  trimmed[space...].trimmingCharacters(in: .whitespaces).hasSuffix(suffix) else { return nil }
            return pid_t(trimmed[..<space])
        }
    }
}

actor CodexAppServerProcess {
    static let restartDelay: Duration = .seconds(5)
    static let staleServerGrace: Duration = .seconds(1)

    let socketPath: String
    private let runner: any ProcessRunning
    private let resolveExecutable: @Sendable () -> String?
    private var process: Process?
    private var supervisor: Task<Void, Never>?

    init(
        socketPath: String,
        runner: any ProcessRunning = SystemProcessRunner(),
        resolveExecutable: @escaping @Sendable () -> String? = { CodexExecutable.resolve() }
    ) {
        self.socketPath = socketPath
        self.runner = runner
        self.resolveExecutable = resolveExecutable
    }

    func start() {
        guard supervisor == nil else { return }
        supervisor = Task { [weak self] in
            await self?.supervise()
        }
    }

    func stop() {
        supervisor?.cancel()
        supervisor = nil
        process?.terminate()
        process = nil
    }

    private func supervise() async {
        while !Task.isCancelled {
            if let executable = resolveExecutable() {
                await runOnce(executable)
            } else {
                codexLogger.error("codex executable not found; Codex tabs stay unavailable")
            }
            try? await Task.sleep(for: Self.restartDelay)
        }
    }

    private func terminateStaleServers() async {
        guard let output = try? await runner.run("/bin/ps", CodexStaleServers.listArguments, timeout: .seconds(5)),
              output.succeeded else { return }
        let stale = CodexStaleServers.pids(inProcessList: output.outputText, socketPath: socketPath)
        guard !stale.isEmpty else { return }
        for pid in stale {
            codexLogger.error("terminating stale codex app-server \(pid, privacy: .public)")
            kill(pid, SIGTERM)
        }
        try? await Task.sleep(for: Self.staleServerGrace)
    }

    private func runOnce(_ executable: String) async {
        await terminateStaleServers()
        guard !Task.isCancelled else { return }
        unlink(socketPath)
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = ["app-server", "--listen", "unix://\(socketPath)"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            codexLogger.error("failed to start codex app-server: \(String(describing: error), privacy: .public)")
            return
        }
        self.process = process
        codexLogger.info("codex app-server started on unix:\(self.socketPath, privacy: .public)")
        for await status in exits {
            codexLogger.error("codex app-server exited with status \(status, privacy: .public)")
        }
        if self.process === process {
            self.process = nil
        }
    }
}
