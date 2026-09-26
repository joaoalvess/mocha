import Foundation

public struct StatusReport: Sendable, Equatable {
    public var text: String
    public var exitCode: Int32

    public static func make(
        local: Result<LocalStatus, LocalControlError>,
        herdrPing: HerdrPing?,
        serve: DoctorItem,
        now: Date
    ) -> StatusReport {
        var lines: [String] = []
        let exitCode: Int32
        switch local {
        case .success(let status):
            exitCode = 0
            lines.append("mochad \(status.version) · no ar há \(ElapsedText.since(status.startedAt, now: now))")
            lines.append("Herdr: " + herdrLine(status.herdr))
            lines.append(status.clients.isEmpty ? "Clientes: nenhum conectado" : "Clientes: \(status.clients.count)")
            for client in status.clients {
                lines.append("  \(client.name) · \(client.deviceId) · conectado há \(ElapsedText.since(client.connectedAt, now: now))")
            }
        case .failure(let error):
            exitCode = 1
            lines.append(error == .notRunning ? DoctorChecks.stoppedHint : "mochad parado? o canal local falhou (\(DoctorChecks.describe(error)))")
            if let herdrPing {
                lines.append("Herdr (ping direto): " + pingLine(herdrPing))
            }
        }
        lines.append("Serve: \(serve.status.symbol) \(serve.summary)")
        lines.append(contentsOf: serve.details.map { "  " + $0 })
        return StatusReport(text: lines.joined(separator: "\n"), exitCode: exitCode)
    }

    static func herdrLine(_ herdr: LocalStatus.Herdr) -> String {
        guard herdr.available else { return "indisponível (o daemon tenta de novo a cada 2 s)" }
        guard let version = herdr.version, let protocolVersion = herdr.protocolVersion else { return "conectado" }
        let info = HerdrServerInfo(version: version, protocolVersion: protocolVersion)
        return "conectado · \(version) · protocolo \(protocolVersion)" + (info.protocolWarning.map { " ⚠️ \($0)" } ?? "")
    }

    static func pingLine(_ ping: HerdrPing) -> String {
        switch ping {
        case .missingSocket(let path):
            return "❌ o socket não existe em \(path)"
        case .failed(let detail):
            return "❌ \(detail)"
        case .reachable(let info):
            return "\(info.version) · protocolo \(info.protocolVersion)" + (info.protocolWarning.map { " ⚠️ \($0)" } ?? "")
        }
    }
}
