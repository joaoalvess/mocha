import Foundation
import MochaDaemonCore

enum ServeSetupCommand {
    static let usage = "uso: mochad serve-setup [--apply | --remove]"

    static func run(_ arguments: [String]) async -> Int32 {
        let options: CommandOptions
        switch CommandOptions.parse(arguments, flags: ["--apply", "--remove"], allowed: [], usage: usage) {
        case .success(let parsed): options = parsed
        case .failure(let error): return Console.fail(error.description, code: 64)
        }
        let inspector: ServeInspector
        do {
            inspector = ServeInspector(gatewayPort: try DaemonConfigStore().read().gatewayPort)
        } catch {
            return Console.fail("config.json inválido: \(error)")
        }
        switch (options.has("--apply"), options.has("--remove")) {
        case (true, true):
            return Console.fail(usage, code: 64)
        case (true, false):
            return await apply(inspector)
        case (false, true):
            return await remove(inspector)
        case (false, false):
            Console.line("O iPhone chega ao gateway pelo Serve do Tailscale:")
            Console.line()
            Console.line("  \(inspector.setupCommand)")
            Console.line()
            Console.line("mochad serve-setup --apply executa, confere e aquece o certificado; --remove desfaz com \(inspector.removeCommand)")
            return 0
        }
    }

    private static func apply(_ inspector: ServeInspector) async -> Int32 {
        Console.line("executando \(inspector.setupCommand)")
        Console.line("depois confiro o handler e aqueço https://<host>\(Gateway.healthPath) (até 90 s)…")
        let diagnosis = await inspector.apply()
        let item = DoctorChecks.serve(diagnosis, setupCommand: inspector.setupCommand, expectedTarget: inspector.expectedTarget)
        Console.line("\(item.status.symbol) \(item.summary)")
        item.details.forEach { Console.line("   " + $0) }
        if case .gatewayNotListening = diagnosis {
            Console.line("   o Serve está configurado; suba o mochad (mochad install ou scripts/run-daemon.sh)")
        }
        return diagnosis.isReady ? 0 : 1
    }

    private static func remove(_ inspector: ServeInspector) async -> Int32 {
        do {
            try await inspector.remove()
            Console.line("handler removido (\(inspector.removeCommand))")
            return 0
        } catch {
            return Console.fail("não consegui remover: \(ServeInspector.describe(error))")
        }
    }
}
