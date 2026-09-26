import Foundation

public enum SigningOutcome: Sendable, Equatable {
    case signed(identity: String)
    case keptExisting
    case missingTeam
    case missingIdentity(team: String)
}

public struct InstallReport: Sendable, Equatable {
    public var binary: URL
    public var copied: Bool
    public var signing: SigningOutcome
    public var generatedHookSecret: Bool
}

public struct DaemonInstaller: Sendable {
    let paths: DaemonPaths
    let signer: CodeSigner
    let launchAgent: LaunchAgent

    public init(paths: DaemonPaths = DaemonPaths(), runner: any ProcessRunning = SystemProcessRunner(), signer: CodeSigner? = nil, userId: uid_t = getuid()) {
        self.paths = paths
        self.signer = signer ?? CodeSigner(runner: runner)
        self.launchAgent = LaunchAgent(paths: paths, runner: runner, userId: userId)
    }

    public func install(executable: URL) async throws -> InstallReport {
        try paths.createSupportDirectory()
        let preparation = try DaemonConfigStore(url: paths.configFile).prepareForDaemon()
        let source = executable.resolvingSymlinksInPath()
        let destination = paths.installedBinary
        let copied = source.standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL
        let signing: SigningOutcome
        if copied {
            try copy(source, to: destination)
            signing = try await sign(destination, team: DevelopmentTeam.locate(from: source).flatMap(DevelopmentTeam.read(xcconfig:)))
        } else {
            signing = .keptExisting
        }
        try await launchAgent.install()
        return InstallReport(binary: destination, copied: copied, signing: signing, generatedHookSecret: preparation.generatedHookSecret)
    }

    @discardableResult
    public func uninstall() async throws -> Bool {
        try await launchAgent.uninstall()
    }

    private func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(try Data(contentsOf: source), to: destination, permissions: 0o755)
    }

    private func sign(_ binary: URL, team: String?) async throws -> SigningOutcome {
        guard let team else { return .missingTeam }
        guard let identity = try await signer.identity(forTeam: team) else { return .missingIdentity(team: team) }
        try await signer.sign(binary.fileSystemPath, with: identity)
        return .signed(identity: identity.name)
    }
}
