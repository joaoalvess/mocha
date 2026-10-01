import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MochaClient

final class FakeDataTransport: HTTPDataTransport {
    enum Reply: Sendable {
        case status(Int, Data)
        case failure
        case notHTTP
    }

    private let reply: Reply
    private let delay: Duration
    private let recorded = Mutex<[URLRequest]>([])
    private let concurrency = Mutex<(running: Int, peak: Int)>((0, 0))

    init(_ reply: Reply, delay: Duration = .zero) {
        self.reply = reply
        self.delay = delay
    }

    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    var peakConcurrency: Int {
        concurrency.withLock { $0.peak }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.withLock { $0.append(request) }
        concurrency.withLock { state in
            state.running += 1
            state.peak = max(state.peak, state.running)
        }
        defer { concurrency.withLock { $0.running -= 1 } }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
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

enum TestImages {
    static func image(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    static func png(width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image(width: width, height: height), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

struct ImageLoaderTests {
    private static let path = "/Users/joao/Library/Application Support/Mocha/uploads/5B1F.jpg"

    private static func loader(
        _ transport: FakeDataTransport,
        pairing: String = "wss://mac-mini.tail1234.ts.net/v1",
        paired: Bool = true
    ) throws -> GatewayImageLoader {
        let credential = paired ? DeviceCredential(url: try #require(URL(string: pairing)), token: "device-token-1") : nil
        return GatewayImageLoader(tokenStore: FakeTokenStore(credential: credential), transport: transport)
    }

    @Test func loadGetsTheImageRouteWithBearerAndDecodesTheBody() async throws {
        let transport = FakeDataTransport(.status(200, try TestImages.png(width: 30, height: 20)))
        let image = try await Self.loader(transport).loadImage(path: Self.path, maxPixelSize: 600)
        #expect(image.width == 30)
        #expect(image.height == 20)
        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token-1")
        #expect(request.url?.absoluteString == "https://mac-mini.tail1234.ts.net/v1/image?path=/Users/joao/Library/Application%20Support/Mocha/uploads/5B1F.jpg&max=600")
    }

    @Test(arguments: [
        ("ws://192.168.0.10:8443/v1", "http://192.168.0.10:8443/v1/image?path=/a.png&max=4096"),
        ("wss://mac.ts.net:8443/v1", "https://mac.ts.net:8443/v1/image?path=/a.png&max=4096"),
        ("ws://joao:secret@mac.local/v1?x=1#f", "http://mac.local/v1/image?path=/a.png&max=4096"),
    ])
    func imageURLKeepsHostAndPortOfThePairing(pairing: String, expected: String) throws {
        let url = GatewayImageLoader.imageURL(forPairingURL: try #require(URL(string: pairing)), path: "/a.png", maxPixelSize: 4_096)
        #expect(url?.absoluteString == expected)
    }

    @Test(arguments: [
        "/Users/joao/Desktop/Captura de Tela 2026-10-01 às 10.00.00.png",
        "/Users/joao/a+b&c=d?e#f%20.png",
        "/Users/joao/fotos/ação.heic",
    ])
    func pathIsPercentEncodedAndRoundTrips(path: String) throws {
        let pairing = try #require(URL(string: "ws://mac.local:9000/v1"))
        let url = try #require(GatewayImageLoader.imageURL(forPairingURL: pairing, path: path, maxPixelSize: 600))
        let query = try #require(url.query(percentEncoded: true))
        #expect(!query.contains(" "))
        #expect(query.hasSuffix("&max=600"))
        #expect(query.components(separatedBy: "&").count == 2)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "path" }?.value == path)
        #expect(items.first { $0.name == "max" }?.value == "600")
    }

    @Test func nonGatewaySchemesHaveNoImageURL() throws {
        #expect(GatewayImageLoader.imageURL(forPairingURL: try #require(URL(string: "mocha://pair")), path: "/a.png", maxPixelSize: 600) == nil)
        #expect(GatewayImageLoader.imageURL(forPairingURL: try #require(URL(string: "ftp://mac.ts.net/v1")), path: "/a.png", maxPixelSize: 600) == nil)
    }

    @Test func withoutPairingNothingIsRequested() async throws {
        let transport = FakeDataTransport(.status(200, Data()))
        await #expect(throws: ImageLoadError.notPaired) {
            try await Self.loader(transport, paired: false).loadImage(path: Self.path, maxPixelSize: 600)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (401, ImageLoadError.unauthorized),
        (404, .notFound),
        (413, .unexpectedStatus(413)),
        (500, .unexpectedStatus(500)),
    ])
    func statusMapsToAnError(status: Int, expected: ImageLoadError) async throws {
        let transport = FakeDataTransport(.status(status, Data()))
        await #expect(throws: expected) {
            try await Self.loader(transport).loadImage(path: Self.path, maxPixelSize: 600)
        }
    }

    @Test func transportFailureIsANetworkError() async throws {
        await #expect(throws: ImageLoadError.network) {
            try await Self.loader(FakeDataTransport(.failure)).loadImage(path: Self.path, maxPixelSize: 600)
        }
        await #expect(throws: ImageLoadError.invalidResponse) {
            try await Self.loader(FakeDataTransport(.notHTTP)).loadImage(path: Self.path, maxPixelSize: 600)
        }
    }

    @Test func bodyThatIsNotAnImageFails() async throws {
        let transport = FakeDataTransport(.status(200, Data("not an image".utf8)))
        await #expect(throws: ImageLoadError.undecodableImage) {
            try await Self.loader(transport).loadImage(path: Self.path, maxPixelSize: 600)
        }
    }

    @Test func atMostFourRequestsRunAtTheSameTime() async throws {
        let transport = FakeDataTransport(.status(200, try TestImages.png(width: 4, height: 4)), delay: .milliseconds(40))
        let loader = try Self.loader(transport)
        try await withThrowingTaskGroup(of: CGImage.self) { group in
            for index in 0..<12 {
                group.addTask { try await loader.loadImage(path: "/tmp/\(index).png", maxPixelSize: 600) }
            }
            try await group.waitForAll()
        }
        #expect(transport.requests.count == 12)
        #expect(transport.peakConcurrency <= GatewayImageLoader.maxConcurrentRequests)
        #expect(transport.peakConcurrency > 1)
    }
}

struct SimulatedImageLoaderTests {
    @Test func gradientIsDeterministicAndBoundedByTheRequestedSize() async throws {
        let loader = SimulatedImageLoader(delay: .zero)
        let first = try await loader.loadImage(path: "/Users/demo/print.png", maxPixelSize: 600)
        let second = try await loader.loadImage(path: "/Users/demo/print.png", maxPixelSize: 600)
        #expect(max(first.width, first.height) == 600)
        #expect(first.width == second.width)
        #expect(first.height == second.height)
        #expect(first.dataProvider?.data as Data? == second.dataProvider?.data as Data?)
        let full = try await loader.loadImage(path: "/Users/demo/print.png", maxPixelSize: 4_096)
        #expect(max(full.width, full.height) == SimulatedImageLoader.largestSide)
    }

    @Test func uploadedImageComesBackFromTheSharedLibrary() async throws {
        let library = SimulatedImageLibrary()
        let uploader = SimulatedImageUploader(delay: .zero, library: library)
        let response = try await uploader.upload(PromptImage(data: try TestImages.png(width: 80, height: 40), contentType: .png))
        let image = try await SimulatedImageLoader(library: library, delay: .zero).loadImage(path: response.path, maxPixelSize: 600)
        #expect(image.width == 80)
        #expect(image.height == 40)
    }
}
