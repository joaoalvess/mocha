#if DEBUG
import Foundation

enum GatewayProbeSessionEvent: Sendable {
    case opened(task: Int)
    case closed(task: Int, code: Int, reason: String?)
    case completed(task: Int, status: Int?, error: String?)
    case metrics(task: Int, protocolName: String?)
}

final class GatewayProbeSessionDelegate: NSObject, URLSessionWebSocketDelegate, Sendable {
    let events: AsyncStream<GatewayProbeSessionEvent>
    private let continuation: AsyncStream<GatewayProbeSessionEvent>.Continuation

    override init() {
        (events, continuation) = AsyncStream.makeStream(of: GatewayProbeSessionEvent.self)
        super.init()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        continuation.yield(.opened(task: webSocketTask.taskIdentifier))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        continuation.yield(.closed(
            task: webSocketTask.taskIdentifier,
            code: closeCode.rawValue,
            reason: reason.map { String(decoding: $0, as: UTF8.self) }
        ))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        continuation.yield(.completed(
            task: task.taskIdentifier,
            status: (task.response as? HTTPURLResponse)?.statusCode,
            error: error.map(GatewayProbeSessionDelegate.describe)
        ))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        continuation.yield(.metrics(
            task: task.taskIdentifier,
            protocolName: metrics.transactionMetrics.last?.networkProtocolName
        ))
    }

    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}

struct GatewayProbeEcho: Codable, Sendable {
    let seq: Int
    let network: String
    let previousRoundTripMs: Double?
    let reconnect: GatewayProbeReconnect?
    let log: [String]?
}

struct GatewayProbeReconnect: Codable, Sendable {
    let reason: String
    let downtimeMs: Int
    let handshakeMs: Int
    let attempts: Int
}

struct GatewayProbeSpikeEcho: Decodable, Sendable {
    let bodyBytes: Int
    let bodySha256: String
    let headers: [[String]]
    let query: String?

    func header(_ name: String) -> String? {
        headers.first { $0.first?.lowercased() == name.lowercased() }.flatMap { $0.count > 1 ? $0[1] : nil }
    }
}
#endif
