import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaClient

final class FakeUploadTransport: HTTPUploadTransport {
    struct Call: Sendable {
        let request: URLRequest
        let body: Data
    }

    enum Reply: Sendable {
        case status(Int, Data)
        case failure
        case notHTTP
    }

    private let reply: Reply
    private let recorded = Mutex<[Call]>([])

    init(_ reply: Reply) {
        self.reply = reply
    }

    var calls: [Call] {
        recorded.withLock { $0 }
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        recorded.withLock { $0.append(Call(request: request, body: bodyData)) }
        let url = try #require(request.url)
        switch reply {
        case .status(let code, let body):
            return (body, try #require(HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)))
        case .failure:
            throw URLError(.timedOut)
        case .notHTTP:
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
    }
}

struct ImageUploaderTests {
    private static let pairingURL = "wss://mac-mini.tail1234.ts.net/v1"
    private static let uploadedPath = "/Users/joao/Library/Application Support/Mocha/uploads/5B1F.jpg"
    private static let image = PromptImage(data: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]), contentType: .jpeg)

    private static func okReply() throws -> FakeUploadTransport.Reply {
        .status(200, try JSONEncoder().encode(UploadResponse(path: uploadedPath)))
    }

    private static func uploader(_ transport: FakeUploadTransport, paired: Bool = true) throws -> GatewayImageUploader {
        let credential = paired ? DeviceCredential(url: try #require(URL(string: pairingURL)), token: "device-token-1") : nil
        return GatewayImageUploader(tokenStore: FakeTokenStore(credential: credential), transport: transport)
    }

    @Test func uploadPostsTheBodyToTheUploadRouteWithBearerAndContentType() async throws {
        let transport = FakeUploadTransport(try Self.okReply())
        let response = try await Self.uploader(transport).upload(Self.image)
        #expect(response == UploadResponse(path: Self.uploadedPath))
        let call = try #require(transport.calls.first)
        #expect(transport.calls.count == 1)
        #expect(call.request.url == URL(string: "https://mac-mini.tail1234.ts.net/v1/upload"))
        #expect(call.request.httpMethod == "POST")
        #expect(call.request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token-1")
        #expect(call.request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(call.request.httpBody == nil)
        #expect(call.request.httpBodyStream == nil)
        #expect(call.body == Self.image.data)
    }

    @Test(arguments: ImageContentType.allCases)
    func contentTypeHeaderFollowsTheImage(type: ImageContentType) async throws {
        let transport = FakeUploadTransport(try Self.okReply())
        _ = try await Self.uploader(transport).upload(PromptImage(data: Data([1]), contentType: type))
        #expect(transport.calls.first?.request.value(forHTTPHeaderField: "Content-Type") == type.rawValue)
    }

    @Test(arguments: [
        ("wss://mac.ts.net/v1", "https://mac.ts.net/v1/upload"),
        ("wss://mac.ts.net:8443/v1?x=1", "https://mac.ts.net:8443/v1/upload"),
        ("ws://127.0.0.1:7777/v1", "http://127.0.0.1:7777/v1/upload"),
    ])
    func uploadURLUsesTheHostOfThePairing(pairing: String, expected: String) throws {
        let url = try #require(URL(string: pairing))
        #expect(GatewayImageUploader.uploadURL(forPairingURL: url) == URL(string: expected))
    }

    @Test func pairingURLWithoutHostOrWithOtherSchemeHasNoUploadURL() throws {
        #expect(GatewayImageUploader.uploadURL(forPairingURL: try #require(URL(string: "mocha://pair"))) == nil)
        #expect(GatewayImageUploader.uploadURL(forPairingURL: try #require(URL(string: "ftp://mac.ts.net/v1"))) == nil)
    }

    @Test func withoutCredentialNothingIsSent() async throws {
        let transport = FakeUploadTransport(.status(200, Data()))
        let uploader = try Self.uploader(transport, paired: false)
        await #expect(throws: ImageUploadError.notPaired) {
            try await uploader.upload(Self.image)
        }
        #expect(transport.calls.isEmpty)
    }

    @Test(arguments: [
        (400, ImageUploadError.emptyBody),
        (401, .unauthorized),
        (411, .lengthRequired),
        (413, .payloadTooLarge),
        (415, .unsupportedMediaType),
        (502, .unexpectedStatus(502)),
    ])
    func errorStatusesMapToUploadErrors(status: Int, expected: ImageUploadError) async throws {
        let uploader = try Self.uploader(FakeUploadTransport(.status(status, Data(#"{"error":"x"}"#.utf8))))
        await #expect(throws: expected) {
            try await uploader.upload(Self.image)
        }
    }

    @Test func transportFailureIsANetworkError() async throws {
        let uploader = try Self.uploader(FakeUploadTransport(.failure))
        await #expect(throws: ImageUploadError.network) {
            try await uploader.upload(Self.image)
        }
    }

    @Test func invalidBodyOrNonHTTPResponseIsInvalid() async throws {
        let invalidBody = try Self.uploader(FakeUploadTransport(.status(200, Data("{}".utf8))))
        let notHTTP = try Self.uploader(FakeUploadTransport(.notHTTP))
        await #expect(throws: ImageUploadError.invalidResponse) {
            try await invalidBody.upload(Self.image)
        }
        await #expect(throws: ImageUploadError.invalidResponse) {
            try await notHTTP.upload(Self.image)
        }
    }

    @Test func simulatedUploaderReturnsAPathInUploadsWithTheExtensionOfTheType() async throws {
        let uploader = SimulatedImageUploader(delay: .zero)
        let jpeg = try await uploader.upload(Self.image).path
        let png = try await uploader.upload(PromptImage(data: Data([1]), contentType: .png)).path
        let prefix = SimulatedImageUploader.uploadsDirectory + "/"
        #expect(jpeg.hasPrefix(prefix) && jpeg.hasSuffix(".jpg"))
        #expect(png.hasPrefix(prefix) && png.hasSuffix(".png"))
        #expect(jpeg != png)
        await #expect(throws: ImageUploadError.emptyBody) {
            try await uploader.upload(PromptImage(data: Data(), contentType: .jpeg))
        }
    }
}
