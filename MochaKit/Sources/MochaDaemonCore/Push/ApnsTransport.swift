import Foundation
import Synchronization

public protocol ApnsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ApnsResponse
}

public struct URLSessionApnsTransport: ApnsTransport {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> ApnsResponse {
        let metrics = ApnsMetricsCollector()
        let (data, response) = try await session.data(for: request, delegate: metrics)
        guard let http = response as? HTTPURLResponse else { throw ApnsError.notHTTPResponse }
        return ApnsResponse(
            status: http.statusCode,
            headerValue: { http.value(forHTTPHeaderField: $0) },
            body: data,
            networkProtocol: metrics.networkProtocol
        )
    }
}

final class ApnsMetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
    private let protocolName = Mutex<String?>(nil)

    var networkProtocol: String? {
        protocolName.withLock { $0 }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let name = metrics.transactionMetrics.last?.networkProtocolName
        protocolName.withLock { $0 = name }
    }
}
