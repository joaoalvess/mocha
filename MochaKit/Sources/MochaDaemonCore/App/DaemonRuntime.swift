import Foundation
import MochaHerdr
import Network
import os

let daemonLogger = Logger(subsystem: "com.joaoalves.mocha", category: "daemon")

public enum DaemonStartError: Error, Sendable, Equatable {
    case portInUse(UInt16)
    case gatewayFailed(String)
    case hookServerFailed(String)
    case controlFailed(String)
}

public struct DaemonOptions: Sendable {
    public var paths: DaemonPaths
    public var herdrSocketPath: String
    public var projectsRoot: String
    public var pairingURL: LocalControl.PairingURLProvider
    public var hookPort: UInt16?
    public var apnsCredentials: ApnsCredentials.Loader?
    public var apnsTransport: (any ApnsTransport)?

    public init(
        paths: DaemonPaths = DaemonPaths(),
        herdrSocketPath: String = HerdrSocketPath.resolve(),
        projectsRoot: String = TranscriptStore.defaultProjectsRoot,
        pairingURL: @escaping LocalControl.PairingURLProvider = { try await TailscaleCLI().webSocketURL() },
        hookPort: UInt16? = nil,
        apnsCredentials: ApnsCredentials.Loader? = nil,
        apnsTransport: (any ApnsTransport)? = nil
    ) {
        self.paths = paths
        self.herdrSocketPath = herdrSocketPath
        self.projectsRoot = projectsRoot
        self.pairingURL = pairingURL
        self.hookPort = hookPort
        self.apnsCredentials = apnsCredentials
        self.apnsTransport = apnsTransport
    }
}

public actor DaemonRuntime {
    public struct Started: Sendable, Equatable {
        public let gatewayPort: UInt16
        public let hookPort: UInt16
        public let controlSocket: String
        public let herdrSocket: String
        public let generatedHookSecret: Bool
    }

    public nonisolated let hookEvents = HookEventHub()

    private let options: DaemonOptions
    private let events: Gateway.EventSink
    private var herdr: HerdrBridge?
    private var usage: UsageMonitor?
    private var gateway: Gateway?
    private var gatewayServer: HttpServer?
    private var hookServer: HttpServer?
    private var controlServer: LocalControlServer?
    private var hookRouter: HookRouter?
    private var push: PushService?
    private var pending: PendingStore?
    private var uploadCleanup: Task<Void, Never>?

    public init(options: DaemonOptions = DaemonOptions(), events: @escaping Gateway.EventSink = { _ in }) {
        self.options = options
        self.events = events
    }

    public func start() async throws -> Started {
        let paths = options.paths
        try paths.createSupportDirectory()
        let preparation = try DaemonConfigStore(url: paths.configFile).prepareForDaemon()
        let port = preparation.config.gatewayPort
        let herdr = HerdrBridge(client: HerdrClient(configuration: HerdrClientConfiguration(socketPath: options.herdrSocketPath)))
        let transcripts = TranscriptStore(projectsRoot: options.projectsRoot)
        let devices = DeviceStore(fileURL: paths.devicesFile)
        let pairing = Pairing()
        let usage = UsageMonitor(cacheFile: paths.usageCacheFile, accountFile: paths.claudeAccountFile)
        let archive = SessionArchive(fileURL: paths.sessionsFile)
        let subagents = SubagentStore(projectsRoot: options.projectsRoot)
        let pending = PendingStore(herdr: herdr, transcripts: transcripts)
        let hub = SessionHub(
            herdr: herdr,
            transcripts: transcripts,
            devices: devices,
            pairing: pairing,
            usage: usage,
            archive: archive,
            subagents: subagents,
            pending: pending
        )
        let push = PushService(
            devices: devices,
            audience: hub,
            credentials: options.apnsCredentials ?? ApnsCredentials.loader(configFile: paths.configFile),
            transport: options.apnsTransport ?? URLSessionApnsTransport()
        )
        let hookRouter = HookRouter(hub: hub, herdr: herdr, push: push)
        let uploads = UploadStore(directory: paths.uploadsDirectory)
        let gateway = Gateway(herdr: herdr, hub: hub, uploads: uploads, events: events)
        let gatewayServer = HttpServer(binding: .loopback(port: port), router: gateway.makeRouter())
        let configFile = paths.configFile
        let hookPort = options.hookPort ?? preparation.config.hookPort
        let hooks = HookServer(
            secrets: HookSecretVerifier(
                secret: preparation.config.hookSecret,
                reload: { (try? DaemonConfigStore(url: configFile).read())?.hookSecret }
            ),
            events: hookEvents,
            permissions: pending,
            resolveAgent: { await herdr.resolve($0) }
        )
        let hookServer = HttpServer(binding: .loopback(port: hookPort), router: hooks.makeRouter())
        let controlServer = LocalControlServer(
            socketPath: paths.controlSocket.fileSystemPath,
            control: LocalControl(
                hub: hub,
                pairing: pairing,
                devices: devices,
                herdr: herdr,
                transcripts: transcripts,
                pairingURL: options.pairingURL,
                apnsIssues: { await push.configurationIssues() }
            )
        )
        self.herdr = herdr
        self.usage = usage
        self.gateway = gateway
        self.push = push
        self.pending = pending
        self.hookRouter = hookRouter
        uploads.removeExpired(now: Date())
        let clock = SystemGatewayClock()
        uploadCleanup = Task {
            await uploads.removeExpiredPeriodically(clock: clock)
        }
        await usage.start()
        await herdr.start()
        await hub.start()
        await pending.start()
        await hookRouter.start(hooks: hookEvents.events())
        do {
            try await gatewayServer.start()
        } catch {
            await stop()
            throw Self.gatewayError(error, port: port)
        }
        self.gatewayServer = gatewayServer
        do {
            try await hookServer.start()
        } catch {
            await stop()
            throw Self.hookServerError(error, port: hookPort)
        }
        self.hookServer = hookServer
        let boundHookPort = await hookServer.port ?? hookPort
        do {
            try await controlServer.start()
        } catch {
            await stop()
            throw DaemonStartError.controlFailed(String(describing: error))
        }
        self.controlServer = controlServer
        daemonLogger.info("mochad \(DaemonVersion.current, privacy: .public) up on 127.0.0.1:\(port, privacy: .public), hooks on 127.0.0.1:\(boundHookPort, privacy: .public)")
        return Started(
            gatewayPort: port,
            hookPort: boundHookPort,
            controlSocket: controlServer.socketPath,
            herdrSocket: options.herdrSocketPath,
            generatedHookSecret: preparation.generatedHookSecret
        )
    }

    public func stop() async {
        await controlServer?.stop()
        controlServer = nil
        await hookServer?.stop()
        hookServer = nil
        await pending?.shutdown()
        pending = nil
        hookEvents.finish()
        await hookRouter?.stop()
        hookRouter = nil
        await push?.shutdown()
        push = nil
        await gateway?.shutdown()
        gateway = nil
        await gatewayServer?.stop()
        gatewayServer = nil
        await herdr?.stop()
        herdr = nil
        await usage?.stop()
        usage = nil
        uploadCleanup?.cancel()
        uploadCleanup = nil
    }

    private static func gatewayError(_ error: any Error, port: UInt16) -> DaemonStartError {
        if case HttpServerError.listenerFailed(.posix(.EADDRINUSE)) = error {
            return .portInUse(port)
        }
        return .gatewayFailed(String(describing: error))
    }

    private static func hookServerError(_ error: any Error, port: UInt16) -> DaemonStartError {
        if case HttpServerError.listenerFailed(.posix(.EADDRINUSE)) = error {
            return .portInUse(port)
        }
        return .hookServerFailed(String(describing: error))
    }
}
