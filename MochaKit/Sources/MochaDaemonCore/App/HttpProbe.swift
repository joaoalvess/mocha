import Foundation

public enum HttpProbeResult: Sendable, Equatable {
    case status(Int)
    case timedOut
    case failed(String)
}

public protocol HttpProbing: Sendable {
    func get(_ url: URL, timeout: Duration) async -> HttpProbeResult
}

public struct URLSessionHttpProbe: HttpProbing {
    public init() {}

    public func get(_ url: URL, timeout: Duration) async -> HttpProbeResult {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = seconds
        configuration.timeoutIntervalForResource = seconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse else { return .failed("resposta sem HTTP") }
            return .status(response.statusCode)
        } catch let error as URLError where error.code == .timedOut {
            return .timedOut
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
