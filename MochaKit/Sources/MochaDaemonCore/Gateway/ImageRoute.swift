import Foundation
import MochaTranscript

struct ImageQuery: Sendable, Equatable {
    let path: String
    let maxPixelSize: Int

    init?(queryItems: [URLQueryItem]) {
        guard let path = queryItems.first(where: { $0.name == "path" })?.value, Self.isAcceptable(path) else { return nil }
        if let max = queryItems.first(where: { $0.name == "max" }) {
            guard let value = max.value.flatMap({ Int($0) }), ImageRoute.maxPixelSizeRange.contains(value) else { return nil }
            maxPixelSize = value
        } else {
            maxPixelSize = ImageRoute.defaultMaxPixelSize
        }
        self.path = path
    }

    static func isAcceptable(_ path: String) -> Bool {
        path.hasPrefix("/")
            && !path.contains("\0")
            && !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }
}

struct ImageRoute: Sendable {
    static let defaultMaxPixelSize = 2_048
    static let maxPixelSizeRange = 64...4_096
    static let maxSourceSize = 50 * 1024 * 1024

    let authenticator: BearerAuthenticator
    let limiter: ImageDecodeLimiter
    let transcriptImages: TranscriptImageCache?

    init(authenticator: BearerAuthenticator, limiter: ImageDecodeLimiter = ImageDecodeLimiter(), transcriptImages: TranscriptImageCache? = nil) {
        self.authenticator = authenticator
        self.limiter = limiter
        self.transcriptImages = transcriptImages
    }

    func respond(to request: HttpRequest) async -> HttpResponse {
        guard await authenticator.device(for: request, marksSeen: false) != nil else { return HttpResponse(status: .unauthorized) }
        guard let image = ImageQuery(queryItems: request.queryItems) else { return HttpResponse(status: .badRequest) }
        guard ImageFileExtension.matches(image.path) else { return HttpResponse(status: .unsupportedMediaType) }
        guard let file = ImageFiles.regularFile(atPath: image.path) else { return HttpResponse(status: .notFound) }
        guard file.size <= Self.maxSourceSize else { return HttpResponse(status: .contentTooLarge) }
        guard ImageFiles.isReadable(file.url) else { return HttpResponse(status: .notFound) }
        await limiter.acquire()
        guard !Task.isCancelled else {
            await limiter.release()
            return HttpResponse(status: .serviceUnavailable)
        }
        let outcome = await Self.transcode(file.url, maxPixelSize: image.maxPixelSize)
        await limiter.release()
        switch outcome {
        case .success(let transcoded):
            transcriptImages?.markUsed(file.url)
            return HttpResponse(status: .ok, headers: ["Content-Type": transcoded.contentType], body: transcoded.data)
        case .failure(.undecodable):
            return HttpResponse(status: .unsupportedMediaType)
        case .failure(.encodingFailed):
            gatewayLogger.error("failed to encode an image for the chat")
            return HttpResponse(status: .internalServerError)
        }
    }

    @concurrent
    private static func transcode(_ url: URL, maxPixelSize: Int) async -> Result<TranscodedImage, ImageTranscodingError> {
        ImageTranscoder.transcode(fileAt: url, maxPixelSize: maxPixelSize)
    }
}
