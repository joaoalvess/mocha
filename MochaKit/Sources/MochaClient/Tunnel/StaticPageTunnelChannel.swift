import Foundation

public struct StaticPageTunnelChannel: TunnelChannel {
    public let html: String

    public init(html: String) {
        self.html = html
    }

    public init(title: String, port: Int) {
        self.init(html: Self.page(title: title, port: port))
    }

    public func exchange(_ body: @Sendable (any TunnelChannelInbound, any TunnelChannelOutbound) async throws -> Void) async throws {
        let (requests, requestSink) = AsyncThrowingStream<Data, any Error>.makeStream()
        let (responses, responseSink) = AsyncThrowingStream<Data, any Error>.makeStream()
        let html = html
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var head = Data()
                for try await chunk in requests {
                    head.append(chunk)
                    if head.range(of: Self.headTerminator) != nil { break }
                }
                responseSink.yield(Self.response(forRequestHead: head, html: html))
                responseSink.finish()
            }
            try await body(AsyncStreamTunnelInbound(responses), AsyncStreamTunnelOutbound(requestSink))
            try await group.waitForAll()
        }
    }

    static let headTerminator = Data("\r\n\r\n".utf8)

    static func requestPath(_ head: Data) -> String? {
        guard
            let line = String(decoding: head, as: UTF8.self).split(separator: "\r\n", maxSplits: 1).first
        else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    static func response(forRequestHead head: Data, html: String) -> Data {
        let path = requestPath(head) ?? "/"
        let isPage = path == "/" || path.hasPrefix("/?") || path == "/index.html"
        let status = isPage ? "200 OK" : "404 Not Found"
        let body = Data((isPage ? html : "").utf8)
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        return Data(header.utf8) + body
    }

    static func page(title: String, port: Int) -> String {
        let escaped = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escaped)</title>
        <style>
        body { margin: 0; font-family: -apple-system, system-ui; background: #f5f3ef; color: #1d1d1f; }
        header { padding: 28px 22px 18px; background: #1f3a2b; color: #fff; }
        header h1 { margin: 0; font-size: 26px; }
        header p { margin: 6px 0 0; opacity: .75; font-size: 14px; }
        main { padding: 20px 22px; display: grid; gap: 14px; }
        .card { background: #fff; border-radius: 14px; padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
        .card h2 { margin: 0 0 6px; font-size: 17px; }
        .card p { margin: 0; color: #5b5b60; font-size: 15px; }
        </style>
        </head>
        <body>
        <header><h1>\(escaped)</h1><p>localhost:\(port) · modo demo</p></header>
        <main>
        <div class="card"><h2>Pedidos</h2><p>12 pedidos abertos, 3 aguardando pagamento.</p></div>
        <div class="card"><h2>Clientes</h2><p>248 clientes ativos neste mês.</p></div>
        <div class="card"><h2>Suporte</h2><p>Nenhum chamado pendente.</p></div>
        </main>
        </body>
        </html>
        """
    }
}
