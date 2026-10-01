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

actor CodexAppServerProcess {
    static let restartDelay: Duration = .seconds(5)

    let socketPath: String
    private var process: Process?
    private var supervisor: Task<Void, Never>?

    init(socketPath: String) {
        self.socketPath = socketPath
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
            if let executable = CodexExecutable.resolve() {
                await runOnce(executable)
            } else {
                codexLogger.error("codex executable not found; Codex tabs stay unavailable")
            }
            try? await Task.sleep(for: Self.restartDelay)
        }
    }

    private func runOnce(_ executable: String) async {
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
