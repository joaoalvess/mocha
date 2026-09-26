import Foundation
import MochaDaemonCore

enum DevicesCommand {
    static let usage = "uso: mochad devices [--remove <id>]"

    static func run(_ arguments: [String]) async -> Int32 {
        let options: CommandOptions
        switch CommandOptions.parse(arguments, allowed: ["--remove"], usage: usage) {
        case .success(let parsed): options = parsed
        case .failure(let error): return Console.fail(error.description, code: 64)
        }
        let paths = DaemonPaths()
        if let id = options.value("--remove") {
            return await remove(id, paths: paths)
        }
        return await list(paths: paths)
    }

    private static func list(paths: DaemonPaths) async -> Int32 {
        let records: [DeviceRecord]
        do {
            records = try await DeviceStore(fileURL: paths.devicesFile).devices()
        } catch {
            return Console.fail("não consegui ler \(paths.display(paths.devicesFile)): \(error)")
        }
        guard !records.isEmpty else {
            Console.line("nenhum aparelho pareado (mochad pair)")
            return 0
        }
        for record in records {
            var line = "\(record.id)  \(record.name)  pareado em \(Console.day(record.createdAt)) · visto em \(Console.day(record.lastSeenAt))"
            if let apns = record.apns {
                line += " · push \(apns.env.rawValue)"
            }
            Console.line(line)
        }
        return 0
    }

    private static func remove(_ id: String, paths: DaemonPaths) async -> Int32 {
        let removal = DeviceRemoval(
            local: LocalControlClient(socketPath: paths.controlSocket.path(percentEncoded: false)),
            store: DeviceStore(fileURL: paths.devicesFile)
        )
        do {
            switch try await removal.remove(id) {
            case .removedByDaemon:
                Console.line("aparelho \(id) removido; as conexões dele foram fechadas")
                return 0
            case .removedFromFile:
                Console.line("mochad parado: aparelho \(id) removido direto de \(paths.display(paths.devicesFile))")
                return 0
            case .notFound:
                return Console.fail("aparelho \(id) não existe")
            }
        } catch let error as LocalControlError {
            return Console.fail("o mochad não removeu o aparelho: \(DoctorChecks.describe(error))")
        } catch {
            return Console.fail("não consegui remover o aparelho: \(error)")
        }
    }
}
