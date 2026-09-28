import Foundation
import MochaClient
import MochaProtocol
import Observation

@MainActor
@Observable
final class BrowserModel {
    enum Phase: Equatable {
        case connecting
        case ready(URL)
        case failed(message: String, pointsToSettings: Bool)
    }

    static let connectingText = "Conectando ao Mac…"

    let server: WebServer
    private(set) var phase: Phase = .connecting
    private(set) var pageTitle: String?
    private(set) var reloadCount = 0

    @ObservationIgnored private let makeTunnel: @MainActor () async throws -> BrowserTunnel
    @ObservationIgnored private var tunnel: BrowserTunnel?
    @ObservationIgnored private var forwarder: TunnelPortForwarder?
    @ObservationIgnored private var localPort: UInt16?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var isClosed = false

    init(server: WebServer, makeTunnel: @escaping @MainActor () async throws -> BrowserTunnel) {
        self.server = server
        self.makeTunnel = makeTunnel
    }

    isolated deinit {
        close()
    }

    var title: String {
        if let pageTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !pageTitle.isEmpty {
            return pageTitle
        }
        return "localhost:\(server.port)"
    }

    func open() {
        guard !isClosed else { return }
        connectTask?.cancel()
        phase = .connecting
        connectTask = Task { await connect(reloadsPage: false) }
    }

    func retry() {
        let forwarder = forwarder
        self.forwarder = nil
        tunnel = nil
        connectTask?.cancel()
        phase = .connecting
        connectTask = Task {
            await forwarder?.stop()
            await connect(reloadsPage: false)
        }
    }

    func reload() {
        guard case .ready = phase else {
            open()
            return
        }
        reloadCount += 1
    }

    func titleChanged(_ title: String?) {
        pageTitle = title
    }

    func pageFailed(_ error: any Error) {
        guard case .ready = phase else { return }
        phase = .failed(message: "Não foi possível carregar a página: \(error.localizedDescription)", pointsToSettings: false)
    }

    func suspend() {
        guard !isClosed, !isSuspended else { return }
        isSuspended = true
        connectTask?.cancel()
        connectTask = nil
        let forwarder = forwarder
        let tunnel = tunnel
        Task {
            await forwarder?.stop()
            await tunnel?.suspend()
        }
    }

    func resume() {
        guard !isClosed, isSuspended else { return }
        isSuspended = false
        connectTask?.cancel()
        connectTask = Task { await connect(reloadsPage: true) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connectTask?.cancel()
        connectTask = nil
        let forwarder = forwarder
        self.forwarder = nil
        Task { await forwarder?.stop() }
    }

    private func connect(reloadsPage: Bool) async {
        do {
            let tunnel = try await currentTunnel()
            try await tunnel.prepare()
            try Task.checkCancellation()
            let forwarder = currentForwarder(tunnel)
            let port = try await forwarder.start(preferredLocalPort: localPort)
            try Task.checkCancellation()
            guard !isClosed else {
                await forwarder.stop()
                return
            }
            localPort = port
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return }
            let wasShowing = phase == .ready(url)
            phase = .ready(url)
            if reloadsPage, wasShowing {
                reloadCount += 1
            }
        } catch is CancellationError {
        } catch let error as SSHSessionError {
            fail(error.localizedDescription, pointsToSettings: error.pointsToSettings)
        } catch {
            fail(error.localizedDescription, pointsToSettings: false)
        }
    }

    private func fail(_ message: String, pointsToSettings: Bool) {
        guard !isClosed, !Task.isCancelled else { return }
        phase = .failed(message: message, pointsToSettings: pointsToSettings)
    }

    private func currentTunnel() async throws -> BrowserTunnel {
        if let tunnel { return tunnel }
        let made = try await makeTunnel()
        tunnel = made
        return made
    }

    private func currentForwarder(_ tunnel: BrowserTunnel) -> TunnelPortForwarder {
        if let forwarder { return forwarder }
        let made = TunnelPortForwarder(remotePort: server.port, openChannel: tunnel.openChannel)
        forwarder = made
        return made
    }
}
