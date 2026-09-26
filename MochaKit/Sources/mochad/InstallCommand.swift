import Foundation
import MochaDaemonCore

enum InstallCommand {
    static func install(_ arguments: [String]) async -> Int32 {
        if case .failure(let error) = CommandOptions.parse(arguments, allowed: [], usage: "uso: mochad install") {
            return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        let installer = DaemonInstaller(paths: paths)
        let report: InstallReport
        do {
            report = try await installer.install(executable: CurrentExecutable.url)
        } catch {
            return Console.fail("mochad install falhou: \(error)")
        }
        Console.line(report.copied ? "binário copiado para \(paths.display(report.binary))" : "binário já em \(paths.display(report.binary))")
        switch report.signing {
        case .signed(let identity):
            Console.line("assinado com \"\(identity)\" (\(CodeSigner.identifier), hardened runtime)")
        case .keptExisting:
            Console.line("assinatura mantida (o binário instalado é o que está rodando)")
        case .missingTeam:
            Console.line("⚠️ sem Config/Signing.xcconfig acima do binário: não assinei, e o Keychain vai pedir autorização a cada build")
        case .missingIdentity(let team):
            Console.line("⚠️ nenhuma identidade Apple Development do time \(team) no Keychain: não assinei, e o Keychain vai pedir autorização a cada build")
        }
        if report.generatedHookSecret {
            Console.line("hookSecret gerado em \(paths.display(paths.configFile))")
        }
        Console.line("LaunchAgent \(LaunchAgent.label) carregado: \(paths.display(paths.launchAgentFile))")
        Console.line("logs em \(paths.display(paths.logFile))")
        Console.line("confira com: launchctl print gui/\(getuid())/\(LaunchAgent.label)")
        return 0
    }

    static func uninstall(_ arguments: [String]) async -> Int32 {
        if case .failure(let error) = CommandOptions.parse(arguments, allowed: [], usage: "uso: mochad uninstall") {
            return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        do {
            let wasLoaded = try await DaemonInstaller(paths: paths).uninstall()
            Console.line(wasLoaded ? "LaunchAgent \(LaunchAgent.label) descarregado" : "LaunchAgent \(LaunchAgent.label) não estava carregado")
            Console.line("plist removido; dados mantidos em \(paths.display(paths.supportDirectory))")
            return 0
        } catch {
            return Console.fail("mochad uninstall falhou: \(error)")
        }
    }
}

enum CurrentExecutable {
    static var url: URL {
        if let path = Bundle.main.executablePath {
            return URL(filePath: path).resolvingSymlinksInPath()
        }
        return URL(filePath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    }
}
