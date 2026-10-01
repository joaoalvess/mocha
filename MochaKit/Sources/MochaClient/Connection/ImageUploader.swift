import Foundation
import MochaProtocol

public enum ImageContentType: String, Sendable, CaseIterable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case heic = "image/heic"

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }
}

public struct PromptImage: Sendable, Equatable {
    public var data: Data
    public var contentType: ImageContentType

    public init(data: Data, contentType: ImageContentType) {
        self.data = data
        self.contentType = contentType
    }
}

public enum ImageUploadError: Error, Sendable, Equatable {
    case notPaired
    case network
    case unauthorized
    case lengthRequired
    case payloadTooLarge
    case unsupportedMediaType
    case emptyBody
    case unexpectedStatus(Int)
    case invalidResponse
}

public protocol ImageUploading: Sendable {
    func upload(_ image: PromptImage) async throws(ImageUploadError) -> UploadResponse
}

public protocol HTTPUploadTransport: Sendable {
    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse)
}

public struct URLSessionUploadTransport: HTTPUploadTransport {
    public static let requestTimeout: TimeInterval = 60

    private let session: URLSession

    public init(session: URLSession = URLSessionUploadTransport.ephemeralSession) {
        self.session = session
    }

    public func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        try await session.upload(for: request, from: bodyData)
    }

    public static let ephemeralSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

public struct GatewayImageUploader: ImageUploading {
    static let uploadPath = "/v1/upload"

    private let tokenStore: any TokenStore
    private let transport: any HTTPUploadTransport

    public init(tokenStore: any TokenStore, transport: any HTTPUploadTransport = URLSessionUploadTransport()) {
        self.tokenStore = tokenStore
        self.transport = transport
    }

    public func upload(_ image: PromptImage) async throws(ImageUploadError) -> UploadResponse {
        guard
            let credential = try? await tokenStore.load(),
            let url = Self.uploadURL(forPairingURL: credential.url)
        else { throw .notPaired }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue(image.contentType.rawValue, forHTTPHeaderField: "Content-Type")
        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await transport.upload(for: request, from: image.data)
        } catch {
            throw .network
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .invalidResponse }
        guard status == 200 else { throw Self.error(forStatus: status) }
        guard let decoded = try? JSONDecoder().decode(UploadResponse.self, from: body) else { throw .invalidResponse }
        return decoded
    }

    static func uploadURL(forPairingURL pairingURL: URL) -> URL? {
        GatewayURL.components(forPairingURL: pairingURL, path: uploadPath)?.url
    }

    static func error(forStatus status: Int) -> ImageUploadError {
        switch status {
        case 400: .emptyBody
        case 401: .unauthorized
        case 411: .lengthRequired
        case 413: .payloadTooLarge
        case 415: .unsupportedMediaType
        default: .unexpectedStatus(status)
        }
    }
}

enum GatewayURL {
    static func components(forPairingURL pairingURL: URL, path: String) -> URLComponents? {
        guard
            var components = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false),
            let host = components.host, !host.isEmpty
        else { return nil }
        switch components.scheme?.lowercased() {
        case "wss", "https":
            components.scheme = "https"
        case "ws", "http":
            components.scheme = "http"
        default:
            return nil
        }
        components.user = nil
        components.password = nil
        components.path = path
        components.query = nil
        components.fragment = nil
        return components
    }
}
