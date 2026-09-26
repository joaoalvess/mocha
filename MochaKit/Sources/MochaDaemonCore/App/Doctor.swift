import Foundation

public struct Doctor: Sendable {
    let paths: DaemonPaths
    let herdr: HerdrProbe
    let local: any LocalControlling
    let serve: ServeInspector
    let signer: CodeSigner
    let keyPresence: any ApnsKeyPresenceChecking
    let executable: URL
    let now: @Sendable () -> Date

    public init(
        paths: DaemonPaths,
        herdr: HerdrProbe,
        local: any LocalControlling,
        serve: ServeInspector,
        signer: CodeSigner,
        keyPresence: any ApnsKeyPresenceChecking,
        executable: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.herdr = herdr
        self.local = local
        self.serve = serve
        self.signer = signer
        self.keyPresence = keyPresence
        self.executable = executable
        self.now = now
    }

    public func run() async -> [DoctorItem] {
        let status = await Self.localStatus(local)
        let settings = ClaudeSettingsInspector(url: paths.claudeSettingsFile).inspect()
        let binary = FileManager.default.fileExists(atPath: paths.installedBinary.fileSystemPath) ? paths.installedBinary : executable
        let config = Result { try ApnsConfigStore(url: paths.configFile).read() }
        let keyPresence = keyPresence
        return [
            DoctorChecks.daemon(status, now: now()),
            DoctorChecks.herdr(await herdr.ping(), socketPath: herdr.socketPath),
            DoctorChecks.agentList(await herdr.agents()),
            DoctorChecks.hooks(settings),
            DoctorChecks.moshiHook(settings),
            DoctorChecks.serve(await serve.diagnose(), setupCommand: serve.setupCommand, expectedTarget: serve.expectedTarget),
            DoctorChecks.apns(
                config: config,
                signature: await signer.signatureStatus(of: binary.fileSystemPath),
                binary: paths.display(binary),
                keychain: { keyPresence.presence(keyId: $0.keyId) },
                issues: (try? status.get())?.apns?.configurationErrors ?? []
            ),
            DoctorChecks.dataDirectory(paths),
            DoctorChecks.transcript(status),
        ]
    }

    public static func localStatus(_ local: any LocalControlling) async -> Result<LocalStatus, LocalControlError> {
        do {
            return .success(try await local.status())
        } catch let error as LocalControlError {
            return .failure(error)
        } catch {
            return .failure(.connectionFailed(String(describing: error)))
        }
    }
}
