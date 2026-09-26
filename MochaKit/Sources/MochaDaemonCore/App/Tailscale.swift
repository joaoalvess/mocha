import Foundation

public enum TailscaleError: Error, Sendable, Equatable {
    case notInstalled(String)
    case commandFailed(command: String, message: String)
    case invalidOutput(command: String)
    case missingDNSName
}

public enum ServeHandler: Sendable, Equatable {
    case proxy(String)
    case other
}

public struct TailscaleServeStatus: Sendable, Equatable {
    public var rootHandlers: [String: ServeHandler]

    public init(rootHandlers: [String: ServeHandler] = [:]) {
        self.rootHandlers = rootHandlers
    }

    public init(json data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TailscaleError.invalidOutput(command: "serve status --json")
        }
        var handlers: [String: ServeHandler] = [:]
        for (hostPort, value) in object["Web"] as? [String: Any] ?? [:] {
            guard let root = ((value as? [String: Any])?["Handlers"] as? [String: Any])?["/"] as? [String: Any] else { continue }
            handlers[hostPort] = (root["Proxy"] as? String).map(ServeHandler.proxy) ?? .other
        }
        rootHandlers = handlers
    }

    public func rootHandler(host: String) -> ServeHandler? {
        rootHandlers["\(host):\(Tailscale.httpsPort)"]
    }
}

public enum Tailscale {
    public static let executable = "/Applications/Tailscale.app/Contents/MacOS/tailscale"
    public static let httpsPort = 443
    public static let commandTimeout: Duration = .seconds(20)
    public static let environment = ["TAILSCALE_BE_CLI": "1"]

    public static func proxyTarget(port: UInt16) -> String {
        "http://127.0.0.1:\(port)"
    }

    public static func serveArguments(port: UInt16) -> [String] {
        ["serve", "--bg", "--https=\(httpsPort)", proxyTarget(port: port)]
    }

    public static let serveOffArguments = ["serve", "--https=\(httpsPort)", "off"]

    public static func displayCommand(_ arguments: [String]) -> String {
        (["tailscale"] + arguments).joined(separator: " ")
    }
}

public struct TailscaleCLI: Sendable {
    public let executable: String
    let runner: any ProcessRunning

    public init(executable: String = Tailscale.executable, runner: any ProcessRunning = SystemProcessRunner()) {
        self.executable = executable
        self.runner = runner
    }

    public func host() async throws -> String {
        let output = try await run(["status", "--json"])
        guard let object = try? JSONSerialization.jsonObject(with: output.standardOutput) as? [String: Any] else {
            throw TailscaleError.invalidOutput(command: "status --json")
        }
        guard let name = (object["Self"] as? [String: Any])?["DNSName"] as? String else {
            throw TailscaleError.missingDNSName
        }
        let host = name.hasSuffix(".") ? String(name.dropLast()) : name
        guard !host.isEmpty else { throw TailscaleError.missingDNSName }
        return host
    }

    public func webSocketURL() async throws -> URL {
        let host = try await host()
        guard let url = URL(string: "wss://\(host)\(Gateway.webSocketPath)") else { throw TailscaleError.missingDNSName }
        return url
    }

    public func serveStatus() async throws -> TailscaleServeStatus {
        try TailscaleServeStatus(json: try await run(["serve", "status", "--json"]).standardOutput)
    }

    public func enableServe(port: UInt16) async throws {
        _ = try await run(Tailscale.serveArguments(port: port))
    }

    public func disableServe() async throws {
        _ = try await run(Tailscale.serveOffArguments)
    }

    private func run(_ arguments: [String]) async throws -> ProcessOutput {
        let output: ProcessOutput
        do {
            output = try await runner.run(executable, arguments, environment: Tailscale.environment, timeout: Tailscale.commandTimeout)
        } catch ProcessRunnerError.notExecutable {
            throw TailscaleError.notInstalled(executable)
        }
        guard output.succeeded else {
            throw TailscaleError.commandFailed(command: Tailscale.displayCommand(arguments), message: output.message)
        }
        return output
    }
}
