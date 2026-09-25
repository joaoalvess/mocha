import Foundation
import MochaDaemonCore

let usage = """
    uso: mochad <comando>

    comandos:
      --version    imprime a versão
    """

switch CommandLine.arguments.dropFirst().first {
case "--version", "version":
    print(DaemonVersion.current)
default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
