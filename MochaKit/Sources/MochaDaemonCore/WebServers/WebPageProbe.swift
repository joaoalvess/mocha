import Foundation
import Synchronization

public enum WebPageProbeResult: Sendable, Equatable {
    case html(Data)
    case notHTML
    case unreachable
}

public protocol WebPageProbing: Sendable {
    func probe(port: Int, timeout: Duration) async -> WebPageProbeResult
}

public struct URLSessionWebPageProbe: WebPageProbing {
    public static let host = "127.0.0.1"
    public static let maxRedirects = 3

    public init() {}

    public func probe(port: Int, timeout: Duration) async -> WebPageProbeResult {
        guard let url = URL(string: "http://\(Self.host):\(port)/") else { return .unreachable }
        let seconds = max(timeout / .seconds(1), 0.001)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = seconds
        configuration.timeoutIntervalForResource = seconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let redirects = SameHostRedirects(host: Self.host, limit: Self.maxRedirects)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: URLRequest(url: url), delegate: redirects)
        } catch {
            return .unreachable
        }
        guard let http = response as? HTTPURLResponse, !(300..<400).contains(http.statusCode), Self.isHTML(http) else {
            return .notHTML
        }
        var body = Data()
        do {
            for try await byte in bytes {
                body.append(byte)
                if body.count >= HTMLTitle.byteLimit { break }
            }
        } catch {
            return .html(body)
        }
        return .html(body)
    }

    static func isHTML(_ response: HTTPURLResponse) -> Bool {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else { return false }
        let mediaType = contentType.split(separator: ";", maxSplits: 1).first ?? ""
        return mediaType.trimmingCharacters(in: .whitespaces).lowercased() == "text/html"
    }
}

final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    private let host: String
    private let limit: Int
    private let followed = Mutex(0)

    init(host: String, limit: Int) {
        self.host = host
        self.limit = limit
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.host() == host else { return nil }
        let allowed = followed.withLock { count in
            count += 1
            return count <= limit
        }
        return allowed ? request : nil
    }
}
