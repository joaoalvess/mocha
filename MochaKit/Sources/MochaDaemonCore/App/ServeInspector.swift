import Foundation

public enum ServeDiagnosis: Sendable, Equatable {
    case ready(host: String)
    case missingHandler(host: String)
    case unixTarget(host: String, target: String)
    case unexpectedTarget(host: String, target: String)
    case gatewayNotListening(host: String)
    case certificatePending(host: String)
    case healthFailed(host: String, detail: String)
    case tailscaleUnavailable(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public struct ServeInspector: Sendable {
    public static let doctorHealthTimeout: Duration = .seconds(15)
    public static let warmUpTimeout: Duration = .seconds(90)

    let tailscale: TailscaleCLI
    let probe: any HttpProbing
    let gatewayPort: UInt16

    public init(tailscale: TailscaleCLI = TailscaleCLI(), probe: any HttpProbing = URLSessionHttpProbe(), gatewayPort: UInt16) {
        self.tailscale = tailscale
        self.probe = probe
        self.gatewayPort = gatewayPort
    }

    public var expectedTarget: String {
        Tailscale.proxyTarget(port: gatewayPort)
    }

    public var setupCommand: String {
        Tailscale.displayCommand(Tailscale.serveArguments(port: gatewayPort))
    }

    public var removeCommand: String {
        Tailscale.displayCommand(Tailscale.serveOffArguments)
    }

    public func diagnose(healthTimeout: Duration = ServeInspector.doctorHealthTimeout) async -> ServeDiagnosis {
        let host: String
        let status: TailscaleServeStatus
        do {
            host = try await tailscale.host()
            status = try await tailscale.serveStatus()
        } catch {
            return .tailscaleUnavailable(Self.describe(error))
        }
        switch status.rootHandler(host: host) {
        case nil, .other:
            return .missingHandler(host: host)
        case .proxy(let target) where target.lowercased().hasPrefix("unix:"):
            return .unixTarget(host: host, target: target)
        case .proxy(let target) where !isExpected(target):
            return .unexpectedTarget(host: host, target: target)
        case .proxy:
            return await checkHealth(host: host, timeout: healthTimeout)
        }
    }

    public func apply() async -> ServeDiagnosis {
        do {
            try await tailscale.enableServe(port: gatewayPort)
        } catch {
            return .tailscaleUnavailable(Self.describe(error))
        }
        return await diagnose(healthTimeout: Self.warmUpTimeout)
    }

    public func remove() async throws {
        try await tailscale.disableServe()
    }

    public static func healthURL(host: String) -> URL? {
        URL(string: "https://\(host)\(Gateway.healthPath)")
    }

    public static func describe(_ error: any Error) -> String {
        switch error {
        case TailscaleError.notInstalled(let path):
            return "Tailscale não encontrado em \(path)"
        case TailscaleError.commandFailed(let command, let message):
            return message.isEmpty ? "\(command) falhou" : "\(command) falhou: \(message)"
        case TailscaleError.invalidOutput(let command):
            return "saída inesperada de tailscale \(command)"
        case TailscaleError.missingDNSName:
            return "tailscale status --json sem Self.DNSName (o Tailscale está conectado?)"
        case ProcessRunnerError.timedOut(let command):
            return "\(command) não respondeu a tempo"
        default:
            return String(describing: error)
        }
    }

    private func isExpected(_ target: String) -> Bool {
        let normalized = target.hasSuffix("/") ? String(target.dropLast()) : target
        return normalized == expectedTarget
    }

    private func checkHealth(host: String, timeout: Duration) async -> ServeDiagnosis {
        guard let url = Self.healthURL(host: host) else { return .healthFailed(host: host, detail: "host inválido") }
        switch await probe.get(url, timeout: timeout) {
        case .status(200):
            return .ready(host: host)
        case .status(502):
            return .gatewayNotListening(host: host)
        case .status(let code):
            return .healthFailed(host: host, detail: "\(Gateway.healthPath) respondeu \(code)")
        case .timedOut:
            return .certificatePending(host: host)
        case .failed(let detail):
            return .healthFailed(host: host, detail: detail)
        }
    }
}
