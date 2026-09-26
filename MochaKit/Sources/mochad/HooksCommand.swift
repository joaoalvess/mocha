import Foundation
import MochaDaemonCore

enum HooksCommand {
    static func install(_ arguments: [String]) -> Int32 {
        if case .failure(let error) = CommandOptions.parse(arguments, allowed: [], usage: "uso: mochad install-hooks") {
            return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        let report: ClaudeHooksReport
        do {
            report = try ClaudeHooksInstaller(paths: paths).install()
        } catch {
            return Console.fail("mochad install-hooks falhou: \(describe(error, paths: paths))")
        }
        let settings = paths.display(report.settingsFile)
        if report.generatedHookSecret {
            Console.line("hookSecret gerado em \(paths.display(paths.configFile))")
        }
        if let backup = report.backup {
            Console.line("backup do original em \(paths.display(backup))")
        }
        Console.line(
            report.changed
                ? "hooks do Mocha instalados em \(settings): \(report.events.joined(separator: ", "))"
                : "hooks do Mocha já estavam instalados em \(settings); nada mudou"
        )
        printMoshiWarning(report.moshiEvents)
        return 0
    }

    static func uninstall(_ arguments: [String]) -> Int32 {
        if case .failure(let error) = CommandOptions.parse(arguments, allowed: [], usage: "uso: mochad uninstall-hooks") {
            return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        let report: ClaudeHooksReport
        do {
            report = try ClaudeHooksInstaller(paths: paths).uninstall()
        } catch {
            return Console.fail("mochad uninstall-hooks falhou: \(describe(error, paths: paths))")
        }
        let settings = paths.display(report.settingsFile)
        if let backup = report.backup {
            Console.line("backup do original em \(paths.display(backup))")
        }
        Console.line(
            report.changed
                ? "hooks do Mocha removidos de \(settings): \(report.events.joined(separator: ", "))"
                : "nenhum hook do Mocha em \(settings); nada mudou"
        )
        printMoshiWarning(report.moshiEvents)
        return 0
    }

    private static func printMoshiWarning(_ events: [String]) {
        guard !events.isEmpty else { return }
        Console.line("⚠️ moshi-hook instalado em \(events.joined(separator: ", ")): os dois decidem o PermissionRequest")
        Console.line("   antes da 1b: moshi-hook uninstall e depois brew services stop moshi-hook")
    }

    private static func describe(_ error: any Error, paths: DaemonPaths) -> String {
        switch error {
        case ClaudeHooksInstallerError.invalidSettings(let path):
            return "\(paths.display(URL(filePath: path))) não é um JSON válido com um objeto na raiz; nada foi alterado"
        case ClaudeHooksInstallerError.unexpectedShape(let path, let key):
            return "\(key) em \(paths.display(URL(filePath: path))) tem um formato inesperado; nada foi alterado"
        case ClaudeHooksInstallerError.unsafeHookSecret:
            return "o hookSecret de \(paths.display(paths.configFile)) tem caracteres fora de base64url; apague a chave para gerar outro"
        case DaemonConfigError.invalidJSON(let path):
            return "\(paths.display(URL(filePath: path))) não é um JSON válido"
        case DaemonConfigError.invalidPort(let field):
            return "\(field) inválido em \(paths.display(paths.configFile))"
        default:
            return String(describing: error)
        }
    }
}
