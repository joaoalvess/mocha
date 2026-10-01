import CoreGraphics
import Foundation
import ImageIO

public enum ImageLoadError: Error, Sendable, Equatable {
    case notPaired
    case network
    case unauthorized
    case notFound
    case unexpectedStatus(Int)
    case invalidResponse
    case undecodableImage
}

public protocol ImageLoading: Sendable {
    func loadImage(path: String, maxPixelSize: Int) async throws(ImageLoadError) -> CGImage
}

public protocol HTTPDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionDataTransport: HTTPDataTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionUploadTransport.ephemeralSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct GatewayImageLoader: ImageLoading {
    public static let maxConcurrentRequests = 4
    static let imagePath = "/v1/image"

    private let tokenStore: any TokenStore
    private let transport: any HTTPDataTransport
    private let limiter: ConcurrencyLimiter

    public init(
        tokenStore: any TokenStore,
        transport: any HTTPDataTransport = URLSessionDataTransport(),
        maxConcurrentRequests: Int = GatewayImageLoader.maxConcurrentRequests
    ) {
        self.tokenStore = tokenStore
        self.transport = transport
        limiter = ConcurrencyLimiter(limit: maxConcurrentRequests)
    }

    public func loadImage(path: String, maxPixelSize: Int) async throws(ImageLoadError) -> CGImage {
        guard
            let credential = try? await tokenStore.load(),
            let url = Self.imageURL(forPairingURL: credential.url, path: path, maxPixelSize: maxPixelSize)
        else { throw .notPaired }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        let (body, response) = try await fetch(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .invalidResponse }
        guard status == 200 else { throw Self.error(forStatus: status) }
        guard let image = Self.decode(body) else { throw .undecodableImage }
        return image
    }

    private func fetch(_ request: URLRequest) async throws(ImageLoadError) -> (Data, URLResponse) {
        await limiter.acquire()
        let result: (Data, URLResponse)?
        do {
            result = try await transport.data(for: request)
        } catch {
            result = nil
        }
        await limiter.release()
        guard let result else { throw .network }
        return result
    }

    static func imageURL(forPairingURL pairingURL: URL, path: String, maxPixelSize: Int) -> URL? {
        guard
            var components = GatewayURL.components(forPairingURL: pairingURL, path: imagePath),
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "path", value: encodedPath),
            URLQueryItem(name: "max", value: String(maxPixelSize)),
        ]
        return components.url
    }

    static func error(forStatus status: Int) -> ImageLoadError {
        switch status {
        case 401: .unauthorized
        case 404: .notFound
        default: .unexpectedStatus(status)
        }
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"
    )
}

actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        guard running >= limit else {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        guard waiting.isEmpty else {
            waiting.removeFirst().resume()
            return
        }
        running = max(0, running - 1)
    }
}
