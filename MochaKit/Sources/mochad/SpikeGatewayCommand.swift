import Foundation
import MochaDaemonCore

enum SpikeGatewayCommand {
    static func run(_ arguments: [String]) async -> Int32 {
        guard let binding = parseBinding(arguments) else {
            FileHandle.standardError.write(Data("uso: mochad spike-gateway --unix <caminho> | --tcp <porta>\n".utf8))
            return 64
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        if case .unixSocket(let path) = binding {
            do {
                try prepareDirectory(for: path)
            } catch {
                SpikeGatewayLog.write("erro ao criar o diretório do socket: \(error)")
                return 1
            }
        }
        let gateway = Gateway(events: SpikeGatewayLog.write)
        var router = gateway.makeRouter()
        gateway.addSpikeRoutes(to: &router)
        let server = HttpServer(binding: binding, router: router)
        do {
            try await server.start()
        } catch {
            SpikeGatewayLog.write("falha ao subir o gateway em \(binding): \(error)")
            return 1
        }
        SpikeGatewayLog.write("gateway \(DaemonVersion.current) ouvindo em \(binding) (pid \(getpid()))")
        let signals = TerminationSignals()
        let received = await signals.next()
        SpikeGatewayLog.write("sinal \(received) recebido, encerrando")
        await server.stop()
        SpikeGatewayLog.write("gateway encerrado")
        return 0
    }

    private static func parseBinding(_ arguments: [String]) -> HttpBinding? {
        guard arguments.count == 2 else { return nil }
        switch arguments[0] {
        case "--unix":
            return arguments[1].hasPrefix("/") ? .unixSocket(path: arguments[1]) : nil
        case "--tcp":
            return UInt16(arguments[1]).map { .loopback(port: $0) }
        default:
            return nil
        }
    }

    private static func prepareDirectory(for socketPath: String) throws {
        let directory = (socketPath as NSString).deletingLastPathComponent
        guard !FileManager.default.fileExists(atPath: directory) else { return }
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

final class TerminationSignals {
    private let sources: [any DispatchSourceSignal]
    private let stream: AsyncStream<Int32>

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Int32.self)
        let queue = DispatchQueue(label: "com.joaoalves.mocha.signals")
        self.stream = stream
        self.sources = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { continuation.yield(number) }
            source.resume()
            return source
        }
    }

    func next() async -> Int32 {
        for await number in stream {
            return number
        }
        return 0
    }
}
