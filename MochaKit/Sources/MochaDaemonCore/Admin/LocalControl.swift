import Foundation
import MochaProtocol
import os

let localControlLogger = Logger(subsystem: "com.joaoalves.mocha", category: "local")

public struct LocalControl: Sendable {
    public typealias PairingURLProvider = @Sendable () async throws -> URL

    public static let pairingCodePath = "/local/pairing-code"
    public static let statusPath = "/local/status"
    public static let devicesPath = "/local/devices/"

    let hub: SessionHub
    let pairing: Pairing
    let devices: DeviceStore
    let herdr: any HerdrBridging
    let transcripts: any TranscriptProviding
    let pairingURL: PairingURLProvider
    let version: String
    let startedAt: Date

    public init(
        hub: SessionHub,
        pairing: Pairing,
        devices: DeviceStore,
        herdr: any HerdrBridging,
        transcripts: any TranscriptProviding,
        pairingURL: @escaping PairingURLProvider,
        version: String = DaemonVersion.current,
        startedAt: Date = Date()
    ) {
        self.hub = hub
        self.pairing = pairing
        self.devices = devices
        self.herdr = herdr
        self.transcripts = transcripts
        self.pairingURL = pairingURL
        self.version = version
        self.startedAt = startedAt
    }

    public static func devicePath(_ id: DeviceID) -> String {
        devicesPath + id
    }

    func makeRouter() async -> HttpRouter {
        var router = HttpRouter()
        router.route(.post, Self.pairingCodePath) { _ in
            try await issuePairingCode()
        }
        router.route(.get, Self.statusPath) { _ in
            try .json(await status(), encoder: LocalJSON.encoder())
        }
        let known = (try? await devices.devices().map(\.id)) ?? []
        for id in known where Self.isRoutable(id) {
            router.route(.delete, Self.devicePath(id)) { _ in
                try await removeDevice(id)
            }
        }
        return router
    }

    public func status() async -> LocalStatus {
        let info = await herdr.serverInfo
        let clients = await hub.connectedClients().map {
            LocalStatus.Client(deviceId: $0.deviceId, name: $0.name, connectedAt: $0.connectedAt)
        }
        var sessions: [LocalStatus.Session] = []
        for followed in await hub.followedSessions() {
            let stats = await transcripts.stats(forSession: TranscriptSession(sessionId: followed.sessionId))
            sessions.append(LocalStatus.Session(
                sessionId: followed.sessionId,
                agentId: followed.agentId,
                claudeVersion: stats?.claudeVersion,
                dropped: stats?.dropped ?? 0,
                orphanResults: stats?.orphanResults ?? 0,
                unknown: stats?.unknown ?? [:]
            ))
        }
        return LocalStatus(
            version: version,
            startedAt: startedAt,
            herdr: LocalStatus.Herdr(available: await herdr.isAvailable, version: info?.version, protocolVersion: info?.protocolVersion),
            clients: clients,
            sessions: sessions
        )
    }

    private func issuePairingCode() async throws -> HttpResponse {
        let url: URL
        do {
            url = try await pairingURL()
        } catch {
            localControlLogger.error("pairing URL unavailable: \(ServeInspector.describe(error), privacy: .public)")
            return try .json(LocalErrorBody(error: ServeInspector.describe(error)), status: .serviceUnavailable)
        }
        return try .json(await pairing.issueCode(url: url), encoder: LocalJSON.encoder())
    }

    private func removeDevice(_ id: DeviceID) async throws -> HttpResponse {
        guard try await hub.removeDevice(id) else { return HttpResponse(status: .notFound) }
        localControlLogger.info("device \(id, privacy: .public) removed")
        return try .json([String: String](), encoder: LocalJSON.encoder())
    }

    static func isRoutable(_ id: DeviceID) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "/" && $0 != "?" && $0 != "#" }
    }
}

extension HttpResponse {
    static func json(_ value: some Encodable, status: HttpStatus = .ok, encoder: JSONEncoder) throws -> HttpResponse {
        HttpResponse(status: status, headers: ["Content-Type": "application/json"], body: try encoder.encode(value))
    }
}
