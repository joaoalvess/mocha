import CryptoKit
import Foundation

enum WebSocketHandshake {
    enum Evaluation {
        case accepted(acceptValue: String)
        case rejected(HttpResponse)
    }

    static let acceptGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    static let supportedVersion = "13"

    static func acceptValue(for key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + acceptGUID).utf8))).base64EncodedString()
    }

    static func evaluate(_ head: HttpRequestHead) -> Evaluation {
        let headers = head.headers
        guard headers.tokens(for: "Upgrade").contains("websocket"),
              headers.tokens(for: "Connection").contains("upgrade")
        else {
            return .rejected(HttpResponse(
                status: .upgradeRequired,
                headers: ["Upgrade": "websocket", "Sec-WebSocket-Version": supportedVersion]
            ))
        }
        guard head.version == "HTTP/1.1" else {
            return .rejected(HttpResponse(status: .badRequest))
        }
        guard headers.values(for: "Sec-WebSocket-Version") == [supportedVersion] else {
            return .rejected(HttpResponse(
                status: .upgradeRequired,
                headers: ["Sec-WebSocket-Version": supportedVersion]
            ))
        }
        let keys = headers.values(for: "Sec-WebSocket-Key")
        guard keys.count == 1, let key = keys.first, Data(base64Encoded: key)?.count == 16 else {
            return .rejected(HttpResponse(status: .badRequest))
        }
        return .accepted(acceptValue: acceptValue(for: key))
    }

    static func switchingProtocolsResponse(acceptValue: String) -> Data {
        Data((
            "HTTP/1.1 101 Switching Protocols\r\n"
                + "Upgrade: websocket\r\n"
                + "Connection: Upgrade\r\n"
                + "Sec-WebSocket-Accept: \(acceptValue)\r\n\r\n"
        ).utf8)
    }
}
