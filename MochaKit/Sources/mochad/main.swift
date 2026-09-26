import Foundation
import MochaDaemonCore

let usage = """
    uso: mochad <comando>

    comandos:
      --version                                   imprime a versão
      spike-gateway --unix <caminho> | --tcp <porta>
                                                  gateway de eco do spike S5 em primeiro plano (temporário)
      apns import | test | liveactivity           chave APNs e envios de teste (mochad apns para detalhes)
    """

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--version", "version":
    print(DaemonVersion.current)
case "spike-gateway":
    exit(await SpikeGatewayCommand.run(Array(arguments.dropFirst())))
case "apns":
    exit(await ApnsCommand.run(Array(arguments.dropFirst())))
default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
