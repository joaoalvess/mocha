import Foundation

public enum LaunchAgentError: Error, Sendable, Equatable {
    case bootstrapFailed(String)
    case bootoutFailed(String)
}

public struct LaunchAgent: Sendable {
    public static let label = "com.joaoalves.mochad"
    public static let launchctl = "/bin/launchctl"
    static let timeout: Duration = .seconds(30)
    static let unloadWait: Duration = .seconds(10)
    static let unloadPollInterval: Duration = .milliseconds(100)
    static let bootstrapAttempts = 3

    let paths: DaemonPaths
    let runner: any ProcessRunning
    let userId: uid_t

    public init(paths: DaemonPaths = DaemonPaths(), runner: any ProcessRunning = SystemProcessRunner(), userId: uid_t = getuid()) {
        self.paths = paths
        self.runner = runner
        self.userId = userId
    }

    public var domain: String {
        "gui/\(userId)"
    }

    public var serviceTarget: String {
        "\(domain)/\(Self.label)"
    }

    public func propertyList() throws -> Data {
        let log = paths.logFile.fileSystemPath
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [paths.installedBinary.fileSystemPath, "run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    public func install() async throws {
        try FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.launchAgentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(try propertyList(), to: paths.launchAgentFile, permissions: 0o644)
        if await isLoaded() {
            _ = try await launchctl(["bootout", serviceTarget])
            try await waitUntilUnloaded()
        }
        var lastFailure = ""
        for attempt in 1...Self.bootstrapAttempts {
            let output = try await launchctl(["bootstrap", domain, paths.launchAgentFile.fileSystemPath])
            if output.succeeded {
                return
            }
            lastFailure = output.message
            if attempt < Self.bootstrapAttempts {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw LaunchAgentError.bootstrapFailed(lastFailure)
    }

    @discardableResult
    public func uninstall() async throws -> Bool {
        let wasLoaded = await isLoaded()
        if wasLoaded {
            let output = try await launchctl(["bootout", serviceTarget])
            if !output.succeeded, await isLoaded() {
                throw LaunchAgentError.bootoutFailed(output.message)
            }
            try await waitUntilUnloaded()
        }
        if FileManager.default.fileExists(atPath: paths.launchAgentFile.fileSystemPath) {
            try FileManager.default.removeItem(at: paths.launchAgentFile)
        }
        return wasLoaded
    }

    public func isLoaded() async -> Bool {
        (try? await launchctl(["print", serviceTarget]))?.succeeded ?? false
    }

    private func waitUntilUnloaded() async throws {
        let deadline = ContinuousClock.now.advanced(by: Self.unloadWait)
        while await isLoaded(), ContinuousClock.now < deadline {
            try await Task.sleep(for: Self.unloadPollInterval)
        }
    }

    private func launchctl(_ arguments: [String]) async throws -> ProcessOutput {
        try await runner.run(Self.launchctl, arguments, timeout: Self.timeout)
    }
}
