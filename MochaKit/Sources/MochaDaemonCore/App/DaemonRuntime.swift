import Foundation
import MochaHerdr
import Network
import os

let daemonLogger = Logger(subsystem: "com.joaoalves.mocha", category: "daemon")

public enum DaemonStartError: Error, Sendable, Equatable {
    case portInUse(UInt16)
    case gatewayFailed(String)
    case controlFailed(String)
}

public struct DaemonOptions: Sendable {
    public var paths: DaemonPaths
    public var herdrSocketPath: String
    public var projectsRoot: String
    public var pairingURL: LocalControl.PairingURLProvider

    public init(
        paths: DaemonPaths = DaemonPaths(),
        herdrSocketPath: String = HerdrSocketPath.resolve(),
        projectsRoot: String = TranscriptStore.defaultProjectsRoot,
        pairingURL: @escaping LocalControl.PairingURLProvider = { try await TailscaleCLI().webSocketURL() }
    ) {
        self.paths = paths
        self.herdrSocketPath = herdrSocketPath
        self.projectsRoot = projectsRoot
        self.pairingURL = pairingURL
    }
}

public actor DaemonRuntime {
    public struct Started: Sendable, Equatable {
        public let gatewayPort: UInt16
        public let controlSocket: String
        public let herdrSocket: String
        public let generatedHookSecret: Bool
    }

    private let options: DaemonOptions
    private let events: Gateway.EventSink
    private var herdr: HerdrBridge?
    private var gateway: Gateway?
    private var gatewayServer: HttpServer?
    private var controlServer: LocalControlServer?

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
        let hub = SessionHub(herdr: herdr, transcripts: transcripts, devices: devices, pairing: pairing)
        let gateway = Gateway(herdr: herdr, hub: hub, events: events)
        let gatewayServer = HttpServer(binding: .loopback(port: port), router: gateway.makeRouter())
        let controlServer = LocalControlServer(
            socketPath: paths.controlSocket.fileSystemPath,
            control: LocalControl(
                hub: hub,
                pairing: pairing,
                devices: devices,
                herdr: herdr,
                transcripts: transcripts,
                pairingURL: options.pairingURL
            )
        )
        self.herdr = herdr
        self.gateway = gateway
        await herdr.start()
        await hub.start()
        do {
            try await gatewayServer.start()
        } catch {
            await stop()
            throw Self.gatewayError(error, port: port)
        }
        self.gatewayServer = gatewayServer
        do {
            try await controlServer.start()
        } catch {
            await stop()
            throw DaemonStartError.controlFailed(String(describing: error))
        }
        self.controlServer = controlServer
        daemonLogger.info("mochad \(DaemonVersion.current, privacy: .public) up on 127.0.0.1:\(port, privacy: .public)")
        return Started(
            gatewayPort: port,
            controlSocket: controlServer.socketPath,
            herdrSocket: options.herdrSocketPath,
            generatedHookSecret: preparation.generatedHookSecret
        )
    }

    public func stop() async {
        await controlServer?.stop()
        controlServer = nil
        await gateway?.shutdown()
        gateway = nil
        await gatewayServer?.stop()
        gatewayServer = nil
        await herdr?.stop()
        herdr = nil
    }

    private static func gatewayError(_ error: any Error, port: UInt16) -> DaemonStartError {
        if case HttpServerError.listenerFailed(.posix(.EADDRINUSE)) = error {
            return .portInUse(port)
        }
        return .gatewayFailed(String(describing: error))
    }
}
