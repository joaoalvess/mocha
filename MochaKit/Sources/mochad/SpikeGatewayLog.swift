import Foundation
import MochaDaemonCore

enum SpikeGatewayLog {
    private static let redactedHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie"]
    private static let maxLoggedText = 8000

    static func write(_ line: String) {
        let timestamp = Date.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current))
        print("\(timestamp) \(line)")
    }

    static func write(_ event: GatewayEvent) {
        switch event {
        case .httpRequest(let request):
            write("http \(request.method.rawValue) \(request.path) query=\(describe(request.query)) corpo=\(request.body.count)B\n" + headerLines(request.headers))
        case .webSocketOpened(let connection, let request):
            write("ws#\(connection) aberto query=\(describe(request.query))\n" + headerLines(request.headers))
        case .webSocketMessage(let connection, let message):
            switch message {
            case .text(let text):
                write("ws#\(connection) msg texto \(text.utf8.count)B \(truncated(text))")
            case .binary(let data):
                write("ws#\(connection) msg binário \(data.count)B")
            }
        case .webSocketClosed(let connection, let code, let reason, let messages, let duration):
            let codeText = code.map { String($0.rawValue) } ?? "nenhum (EOF sem close)"
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            write("ws#\(connection) fechado código=\(codeText) motivo=\(describe(reason)) msgs=\(messages) duração=\(String(format: "%.1f", seconds))s")
        }
    }

    private static func headerLines(_ headers: HttpHeaders) -> String {
        headers.map { field in
            let value = redactedHeaders.contains(field.name.lowercased()) ? "<redigido, \(field.value.utf8.count) bytes>" : field.value
            return "    \(field.name): \(value)"
        }.joined(separator: "\n")
    }

    private static func describe(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return "\"\(value)\""
    }

    private static func truncated(_ text: String) -> String {
        text.count > maxLoggedText ? String(text.prefix(maxLoggedText)) + "…" : text
    }
}
