import Foundation
import MochaDaemonCore
import MochaProtocol

enum PairCommand {
    static func run(_ arguments: [String]) async -> Int32 {
        if case .failure(let error) = CommandOptions.parse(arguments, allowed: [], usage: "uso: mochad pair") {
            return Console.fail(error.description, code: 64)
        }
        let code: PairingCode
        do {
            code = try await LocalControlClient().pairingCode()
        } catch LocalControlError.notRunning {
            return Console.fail("o mochad não está rodando. Suba com mochad install (LaunchAgent) ou scripts/run-daemon.sh e tente de novo.")
        } catch let error as LocalControlError {
            return Console.fail("o mochad não gerou o código: \(DoctorChecks.describe(error))")
        } catch {
            return Console.fail("o mochad não gerou o código: \(error)")
        }
        let link = code.link.link.absoluteString
        guard let qr = TerminalQRCode.render(link) else {
            return Console.fail("não consegui gerar o QR")
        }
        Console.line("Leia com a câmera do iPhone ou na tela de pareamento do Mocha:")
        Console.line()
        Console.line(qr)
        Console.line()
        Console.line("Link: \(link)")
        Console.line("Servidor: \(code.url.absoluteString)")
        Console.line("Vale até \(Console.clock(code.expiresAt)) (\(Int(Pairing.codeValidity / 60)) min), uma vez só.")
        return 0
    }
}
