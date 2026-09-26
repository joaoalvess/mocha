import Foundation
import MochaDaemonCore
import MochaHerdr

enum RunCommand {
    static let usage = "uso: mochad run [--herdr-socket <caminho>]"

    static func run(_ arguments: [String]) async -> Int32 {
        let options: CommandOptions
        switch CommandOptions.parse(arguments, allowed: ["--herdr-socket"], usage: usage) {
        case .success(let parsed): options = parsed
        case .failure(let error): return Console.fail(error.description, code: 64)
        }
        let signals = TerminationSignals()
        let herdrSocket = HerdrSocketPath.resolve(override: options.value("--herdr-socket"))
        let runtime = DaemonRuntime(options: DaemonOptions(herdrSocketPath: herdrSocket), events: log)
        let started: DaemonRuntime.Started
        do {
            started = try await runtime.start()
        } catch DaemonStartError.portInUse(let port) {
            return Console.fail(
                "mochad: a porta 127.0.0.1:\(port) já está em uso (EADDRINUSE). Outro mochad está rodando? "
                    + "Veja mochad status ou lsof -nP -iTCP:\(port) -sTCP:LISTEN"
            )
        } catch {
            return Console.fail("mochad: não consegui subir: \(error)")
        }
        stamp("mochad \(DaemonVersion.current) no ar (pid \(getpid()))")
        stamp("gateway em 127.0.0.1:\(started.gatewayPort) · hooks em 127.0.0.1:\(started.hookPort) · canal local em \(started.controlSocket)")
        stamp("Herdr em \(started.herdrSocket)")
        if started.generatedHookSecret {
            stamp("hookSecret gerado no config.json")
        }
        let signal = await signals.next()
        stamp("recebi \(signal == SIGINT ? "SIGINT" : "SIGTERM"); encerrando")
        await runtime.stop()
        stamp("encerrado")
        return 0
    }

    private static func stamp(_ text: String) {
        Console.line("\(Console.timestamp()) \(text)")
    }

    @Sendable private static func log(_ event: GatewayEvent) {
        switch event {
        case .httpRequest:
            break
        case .webSocketOpened(let connection, let request):
            stamp("ws #\(connection) aberto (\(request.headers["X-Forwarded-For"] ?? "local"))")
        case .webSocketClosed(let connection, let code, _, let duration):
            stamp("ws #\(connection) fechado (\(code.map { String($0.rawValue) } ?? "sem close"), \(duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))))")
        }
    }
}
