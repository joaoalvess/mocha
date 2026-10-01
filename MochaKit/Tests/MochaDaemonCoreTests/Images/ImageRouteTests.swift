import CoreGraphics
import Foundation
import MochaProtocol
import Testing
import UniformTypeIdentifiers
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct ImageRouteTests {
    private struct Harness {
        let port: UInt16
        let token: String
        let device: DeviceRecord
        let files: URL
        let hub: HubHarness

        func get(path: String?, max: String? = nil, token: String? = nil, authorized: Bool = true) async throws -> TestHttpResponse {
            var headers: [String: String] = [:]
            if authorized {
                headers["Authorization"] = "Bearer \(token ?? self.token)"
            }
            return try await sendRequest("GET", port: port, target: ImageRouteTests.target(path: path, max: max), headers: headers)
        }
    }

    private static func target(path: String?, max: String?) -> String {
        var components = URLComponents()
        components.path = Gateway.imagePath
        var items: [URLQueryItem] = []
        if let path {
            items.append(URLQueryItem(name: "path", value: path))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: max))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? Gateway.imagePath
    }

    private func withImageGateway(transcriptImages: String? = nil, _ body: (Harness) async throws -> Void) async throws {
        try await withHub { hub in
            let token = SecureToken.generate()
            let device = try await hub.devices.register(name: "iPhone do João", token: token, at: Sample.start)
            let files = try TestImages.directory()
            defer { try? FileManager.default.removeItem(at: files) }
            let cache = transcriptImages.map { TranscriptImageCache(directory: files.appending(path: $0, directoryHint: .isDirectory)) }
            let gateway = Gateway(version: "9.9.9", herdr: hub.herdr, hub: hub.hub, transcriptImages: cache)
            try await withRunningServer(gateway.makeRouter()) { port in
                try await body(Harness(port: port, token: token, device: device, files: files, hub: hub))
            }
        }
    }

    private func jpeg(_ harness: Harness, width: Int = 120, height: Int = 80, name: String = "foto.jpg") throws -> URL {
        try TestImages.write(try TestImages.solid(width: width, height: height), to: harness.files.appending(path: name), type: .jpeg)
    }

    @Test func routeIsRegisteredEvenWithoutAnUploadStore() async throws {
        #expect(Gateway.imagePath == "/v1/image")
        try await withImageGateway { harness in
            let response = try await harness.get(path: "/tmp/a.png", authorized: false)
            #expect(response.status == 401)
            #expect(response.body.isEmpty)
        }
    }

    @Test func missingOrUnknownBearerGets401BeforeAnyOtherCheck() async throws {
        try await withImageGateway { harness in
            let file = try jpeg(harness).fileSystemPath
            #expect(try await harness.get(path: file, authorized: false).status == 401)
            #expect(try await harness.get(path: file, token: "desconhecido").status == 401)
            #expect(try await harness.get(path: file, token: SecureToken.sha256Hex(harness.token)).status == 401)
            #expect(try await harness.get(path: nil, authorized: false).status == 401)
            #expect(try await harness.get(path: "relativo.png", max: "1", authorized: false).status == 401)
        }
    }

    @Test func validBearerDoesNotMarkTheDeviceAsSeen() async throws {
        try await withImageGateway { harness in
            harness.hub.clock.advance(by: .seconds(90))
            let response = try await harness.get(path: try jpeg(harness).fileSystemPath)
            #expect(response.status == 200)
            let record = try #require(try await harness.hub.devices.devices().first { $0.id == harness.device.id })
            #expect(record.lastSeenAt == Sample.start)
        }
    }

    @Test func invalidPathOrMaxGets400() async throws {
        try await withImageGateway { harness in
            let file = try jpeg(harness).fileSystemPath
            let directory = harness.files.fileSystemPath
            #expect(try await harness.get(path: nil).status == 400)
            #expect(try await harness.get(path: "").status == 400)
            #expect(try await harness.get(path: "foto.jpg").status == 400)
            #expect(try await harness.get(path: "~/foto.jpg").status == 400)
            #expect(try await harness.get(path: "\(directory)/../\(harness.files.lastPathComponent)/foto.jpg").status == 400)
            #expect(try await harness.get(path: "\(directory)/./foto.jpg").status == 400)
            #expect(try await harness.get(path: "\(directory)/..").status == 400)
            for max in ["63", "4097", "0", "-64", "abc", "", "2048.0"] {
                #expect(try await harness.get(path: file, max: max).status == 400, "max=\(max)")
            }
            #expect(try await harness.get(path: file, max: "64").status == 200)
            #expect(try await harness.get(path: file, max: "4096").status == 200)
        }
    }

    @Test func pathThatIsNotARegularFileGets404() async throws {
        try await withImageGateway { harness in
            let folder = harness.files.appending(path: "pasta.png", directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(folder.fileSystemPath.hasSuffix("/pasta.png"))
            #expect(try await harness.get(path: harness.files.appending(path: "nao-existe.png").fileSystemPath).status == 404)
            #expect(try await harness.get(path: folder.fileSystemPath).status == 404)
        }
    }

    @Test func permissionErrorsCountAsMissing() async throws {
        try await withImageGateway { harness in
            let unreadable = try jpeg(harness, name: "sem-leitura.jpg")
            try TestImages.setPermissions(0o000, of: unreadable)
            let closed = harness.files.appending(path: "fechada", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
            let inside = try jpeg(harness, name: "fechada/dentro.jpg")
            try TestImages.setPermissions(0o000, of: closed)
            defer {
                try? TestImages.setPermissions(0o700, of: closed)
                try? TestImages.setPermissions(0o600, of: unreadable)
            }
            #expect(try await harness.get(path: unreadable.fileSystemPath).status == 404)
            #expect(try await harness.get(path: inside.fileSystemPath).status == 404)
        }
    }

    @Test func sourceAboveFiftyMebibytesGets413() async throws {
        #expect(ImageRoute.maxSourceSize == 50 * 1024 * 1024)
        try await withImageGateway { harness in
            let above = harness.files.appending(path: "grande.png")
            try TestImages.sparseFile(at: above, size: ImageRoute.maxSourceSize + 1)
            #expect(try await harness.get(path: above.fileSystemPath).status == 413)

            let exact = harness.files.appending(path: "limite.png")
            try TestImages.sparseFile(at: exact, size: ImageRoute.maxSourceSize)
            #expect(try await harness.get(path: exact.fileSystemPath).status == 415)
        }
    }

    @Test func otherExtensionsAndUndecodableImagesGet415() async throws {
        try await withImageGateway { harness in
            let text = harness.files.appending(path: "notas.txt")
            try Data("não é imagem".utf8).write(to: text)
            #expect(try await harness.get(path: text.fileSystemPath).status == 415)

            let disguisedJPEG = try jpeg(harness, name: "foto.bmp")
            #expect(try await harness.get(path: disguisedJPEG.fileSystemPath).status == 415)

            let garbage = harness.files.appending(path: "lixo.png")
            try Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: garbage)
            #expect(try await harness.get(path: garbage.fileSystemPath).status == 415)

            #expect(try await harness.get(path: harness.files.appending(path: "nao-existe.txt").fileSystemPath).status == 415)
        }
    }

    @Test func jpegIsReducedToMaxOnTheLargestSide() async throws {
        try await withImageGateway { harness in
            let source = try jpeg(harness, width: 1_000, height: 500)
            let response = try await harness.get(path: source.fileSystemPath, max: "200")
            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "image/jpeg")
            #expect(TestImages.typeIdentifier(of: response.body) == UTType.jpeg.identifier)
            let image = try TestImages.decode(response.body)
            #expect(Swift.max(image.width, image.height) <= 200)
            #expect(image.width == 200)
            #expect(image.height == 100)
            #expect(try response.body != Data(contentsOf: source))
        }
    }

    @Test func missingMaxDefaultsTo2048() async throws {
        try await withImageGateway { harness in
            let source = try TestImages.write(try TestImages.solid(width: 2_600, height: 100), to: harness.files.appending(path: "larga.png"), type: .png)
            let response = try await harness.get(path: source.fileSystemPath)
            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "image/jpeg")
            let image = try TestImages.decode(response.body)
            #expect(image.width == ImageRoute.defaultMaxPixelSize)
        }
    }

    @Test func smallImageIsNotEnlargedButIsStillReencoded() async throws {
        try await withImageGateway { harness in
            let source = try jpeg(harness, width: 100, height: 50)
            let response = try await harness.get(path: source.fileSystemPath, max: "4096")
            #expect(response.status == 200)
            let image = try TestImages.decode(response.body)
            #expect(image.width == 100)
            #expect(image.height == 50)
            #expect(try response.body != Data(contentsOf: source))
        }
    }

    @Test func pngWithAlphaStaysPNG() async throws {
        try await withImageGateway { harness in
            let transparent = try TestImages.image(width: 64, height: 64, hasAlpha: true) { context in
                context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
                context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
            }
            let source = try TestImages.write(transparent, to: harness.files.appending(path: "alfa.png"), type: .png)
            let response = try await harness.get(path: source.fileSystemPath)
            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "image/png")
            #expect(TestImages.typeIdentifier(of: response.body) == UTType.png.identifier)
            let image = try TestImages.decode(response.body)
            #expect(try TestImages.pixel(image, x: 48, y: 32).alpha == 0)
            #expect(try TestImages.pixel(image, x: 16, y: 32).isMostlyRed)
        }
    }

    @Test func opaquePNGBecomesJPEG() async throws {
        try await withImageGateway { harness in
            let source = try TestImages.write(try TestImages.solid(width: 64, height: 64), to: harness.files.appending(path: "opaca.PNG"), type: .png)
            let response = try await harness.get(path: source.fileSystemPath)
            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "image/jpeg")
        }
    }

    @Test func exifOrientationIsApplied() async throws {
        try await withImageGateway { harness in
            let stored = try TestImages.image(width: 400, height: 200) { context in
                context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
                context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
                context.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
            }
            let source = try TestImages.write(stored, to: harness.files.appending(path: "girada.jpg"), type: .jpeg, orientation: .right)
            let response = try await harness.get(path: source.fileSystemPath, max: "300")
            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "image/jpeg")
            let image = try TestImages.decode(response.body)
            #expect(image.width == 150)
            #expect(image.height == 300)
            #expect(try TestImages.pixel(image, x: 75, y: 40).isMostlyRed)
            #expect(try TestImages.pixel(image, x: 75, y: 260).isMostlyBlue)
        }
    }

    @Test func symlinkToAnImageIsServed() async throws {
        try await withImageGateway { harness in
            let target = try jpeg(harness)
            let link = harness.files.appending(path: "atalho.jpg")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(try await harness.get(path: link.fileSystemPath).status == 200)
        }
    }

    @Test func servingAFileOfTheTranscriptImageCacheRenewsItsDate() async throws {
        try await withImageGateway(transcriptImages: "transcript-images") { harness in
            let cache = harness.files.appending(path: "transcript-images", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let cached = try jpeg(harness, name: "transcript-images/abc.jpg")
            let outside = try jpeg(harness, name: "fora.jpg")
            let broken = cache.appending(path: "quebrada.jpg")
            try Data("não é imagem".utf8).write(to: broken)
            let old = Date(timeIntervalSince1970: 1_600_000_000)
            for file in [cached, outside, broken] {
                try setModificationDate(old, of: file)
            }

            #expect(try await harness.get(path: cached.fileSystemPath).status == 200)
            #expect(try await harness.get(path: outside.fileSystemPath).status == 200)
            #expect(try await harness.get(path: broken.fileSystemPath).status == 415)

            #expect(try Date().timeIntervalSince(Self.modificationDate(cached)) < 60)
            #expect(try Self.modificationDate(outside) == old)
            #expect(try Self.modificationDate(broken) == old)
        }
    }

    @Test func withoutACacheNothingIsRenewed() async throws {
        try await withImageGateway { harness in
            let file = try jpeg(harness, name: "abc.jpg")
            let old = Date(timeIntervalSince1970: 1_600_000_000)
            try setModificationDate(old, of: file)
            #expect(try await harness.get(path: file.fileSystemPath).status == 200)
            #expect(try Self.modificationDate(file) == old)
        }
    }

    private static func modificationDate(_ url: URL) throws -> Date {
        try #require(try FileManager.default.attributesOfItem(atPath: url.fileSystemPath)[.modificationDate] as? Date)
    }

    @Test func queryParsingFollowsTheContract() {
        let defaults = ImageQuery(queryItems: [URLQueryItem(name: "path", value: "/a/b.png")])
        #expect(defaults?.path == "/a/b.png")
        #expect(defaults?.maxPixelSize == 2_048)
        #expect(ImageQuery(queryItems: [URLQueryItem(name: "path", value: "/a/b.png"), URLQueryItem(name: "max", value: "600")])?.maxPixelSize == 600)
        #expect(ImageQuery(queryItems: [URLQueryItem(name: "path", value: "/a/b\0.png")]) == nil)
        #expect(ImageQuery(queryItems: [URLQueryItem(name: "path", value: nil)]) == nil)
        #expect(ImageQuery(queryItems: [URLQueryItem(name: "path", value: "/a/b.png"), URLQueryItem(name: "max", value: nil)]) == nil)
        #expect(ImageQuery.isAcceptable("/a//b.png"))
        #expect(ImageQuery.isAcceptable("/a/..b/c.png"))
        #expect(ImageQuery.isAcceptable("/a/../c.png") == false)
    }
}
