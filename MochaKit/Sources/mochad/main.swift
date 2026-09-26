import Foundation
import MochaDaemonCore

let usage = """
    uso: mochad <comando>

    comandos:
      run [--herdr-socket <caminho>]      roda o daemon em primeiro plano (é o que o LaunchAgent chama)
      install                             copia para ~/.local/bin, assina e carrega o LaunchAgent
      uninstall                           descarrega o LaunchAgent e remove o plist (mantém os dados)
      pair                                pede ao daemon um código e mostra o QR de pareamento
      devices [--remove <id>]             lista ou remove aparelhos pareados
      serve-setup [--apply | --remove]    mostra, aplica ou desfaz o tailscale serve
      status [--herdr-socket <caminho>]   daemon, Herdr, clientes e Serve
      doctor [--herdr-socket <caminho>]   diagnóstico com ✅/⚠️/❌
      apns import | test | liveactivity   chave APNs e envios de teste (mochad apns para detalhes)
      --version                           imprime a versão
    """

let arguments = Array(CommandLine.arguments.dropFirst())
let rest = Array(arguments.dropFirst())

switch arguments.first {
case "--version", "version":
    print(DaemonVersion.current)
case "run":
    exit(await RunCommand.run(rest))
case "install":
    exit(await InstallCommand.install(rest))
case "uninstall":
    exit(await InstallCommand.uninstall(rest))
case "pair":
    exit(await PairCommand.run(rest))
case "devices":
    exit(await DevicesCommand.run(rest))
case "serve-setup":
    exit(await ServeSetupCommand.run(rest))
case "status":
    exit(await StatusCommand.status(rest))
case "doctor":
    exit(await StatusCommand.doctor(rest))
case "apns":
    exit(await ApnsCommand.run(rest))
default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
