import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite(.timeLimit(.minutes(1)))
struct UploadRouteTests {
    private struct Harness {
        let port: UInt16
        let token: String
        let device: DeviceRecord
        let uploads: URL
        let hub: HubHarness
    }

    private func withUploadGateway(_ body: (Harness) async throws -> Void) async throws {
        try await withHub { hub in
            let token = SecureToken.generate()
            let device = try await hub.devices.register(name: "iPhone do João", token: token, at: Sample.start)
            let uploads = hub.directory.appending(path: "uploads", directoryHint: .isDirectory)
            let gateway = Gateway(version: "9.9.9", herdr: hub.herdr, hub: hub.hub, uploads: UploadStore(directory: uploads))
            try await withRunningServer(gateway.makeRouter()) { port in
                try await body(Harness(port: port, token: token, device: device, uploads: uploads, hub: hub))
            }
        }
    }

    @Test(arguments: UploadImageType.allCases)
    func acceptsEachImageTypeAndAnswersWithThePathInUploads(_ type: UploadImageType) async throws {
        try await withUploadGateway { harness in
            let body = UploadSamples.bytes(for: type)
            let response = try await sendRequest(
                "POST",
                port: harness.port,
                target: Gateway.uploadPath,
                headers: ["Authorization": "Bearer \(harness.token)", "Content-Type": type.rawValue],
                body: Data(body)
            )

            #expect(response.status == 200)
            #expect(response.header("Content-Type") == "application/json")
            let upload = try JSONDecoder().decode(UploadResponse.self, from: response.body)
            let file = URL(filePath: upload.path)
            #expect(upload.path.hasPrefix("/"))
            #expect(file.deletingLastPathComponent().fileSystemPath == harness.uploads.fileSystemPath)
            #expect(isUUIDFileName(file.lastPathComponent, extension: type.fileExtension))
            #expect(try Data(contentsOf: file) == Data(body))
            #expect(fileMode(file) == 0o600)
            #expect(fileMode(harness.uploads) == 0o700)
            #expect(directoryEntries(harness.uploads) == [file.lastPathComponent])
        }
    }

    @Test func responseBodyUsesTheProtocolEncoding() async throws {
        try await withUploadGateway { harness in
            let response = try await UploadRequests.image(port: harness.port, token: harness.token, body: UploadSamples.jpeg)
            #expect(response.status == 200)
            let object = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            #expect(object.keys.sorted() == ["path"])
            #expect(!String(decoding: response.body, as: UTF8.self).contains("\\/"))
        }
    }

    @Test(arguments: [
        [String](),
        ["Authorization: Bearer desconhecido"],
        ["Authorization: Bearer "],
        ["Authorization: Basic dXNlcjpwYXNz"],
        ["Authorization: TOKEN"],
    ])
    func missingOrInvalidBearerGets401(_ authorization: [String]) async throws {
        try await withUploadGateway { harness in
            var headers: [(String, String)] = [("Content-Type", "image/jpeg")]
            for line in authorization {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                headers.append((parts[0], parts.count > 1 ? parts[1] : ""))
            }
            let response = try await UploadRequests.post(port: harness.port, headers: headers, body: UploadSamples.jpeg)
            #expect(response.status == 401)
            #expect(response.body.isEmpty)
            #expect(directoryEntries(harness.uploads).isEmpty)
        }
    }

    @Test func tokenHashOrAnotherDevicesRemovedTokenGets401() async throws {
        try await withUploadGateway { harness in
            let hashed = try await UploadRequests.image(port: harness.port, token: SecureToken.sha256Hex(harness.token), body: UploadSamples.jpeg)
            #expect(hashed.status == 401)

            let other = SecureToken.generate()
            let removed = try await harness.hub.devices.register(name: "iPad", token: other, at: Sample.start)
            #expect(try await UploadRequests.image(port: harness.port, token: other, body: UploadSamples.jpeg).status == 200)
            #expect(try await harness.hub.devices.remove(removed.id))
            #expect(try await UploadRequests.image(port: harness.port, token: other, body: UploadSamples.jpeg).status == 401)
            #expect(directoryEntries(harness.uploads).count == 1)
        }
    }

    @Test func validBearerMarksTheDeviceAsSeenLikeHello() async throws {
        try await withUploadGateway { harness in
            harness.hub.clock.advance(by: .seconds(90))

            let response = try await UploadRequests.image(port: harness.port, token: harness.token, body: UploadSamples.png)

            #expect(response.status == 200)
            let record = try #require(try await harness.hub.devices.devices().first { $0.id == harness.device.id })
            #expect(record.lastSeenAt == Sample.start.addingTimeInterval(90))
        }
    }

    @Test func bearerParsingRequiresExactlyOneBearerCredential() {
        #expect(BearerAuthenticator.token(in: ["Authorization": "Bearer abc"]) == "abc")
        #expect(BearerAuthenticator.token(in: ["authorization": "bearer abc "]) == "abc")
        #expect(BearerAuthenticator.token(in: [:]) == nil)
        #expect(BearerAuthenticator.token(in: ["Authorization": "Bearer"]) == nil)
        #expect(BearerAuthenticator.token(in: ["Authorization": "Bearer    "]) == nil)
        #expect(BearerAuthenticator.token(in: ["Authorization": "Basic abc"]) == nil)
        #expect(BearerAuthenticator.token(in: HttpHeaders([
            HttpHeaders.Field(name: "Authorization", value: "Bearer abc"),
            HttpHeaders.Field(name: "Authorization", value: "Bearer def"),
        ])) == nil)
    }

    @Test func requestWithoutContentLengthGets411() async throws {
        try await withUploadGateway { harness in
            let missing = try await UploadRequests.post(
                port: harness.port,
                headers: [("Authorization", "Bearer \(harness.token)"), ("Content-Type", "image/jpeg"), ("Connection", "close")],
                body: [],
                sendsContentLength: false
            )
            #expect(missing.status == 411)

            let chunked = try await UploadRequests.post(
                port: harness.port,
                headers: [("Authorization", "Bearer \(harness.token)"), ("Content-Type", "image/jpeg"), ("Transfer-Encoding", "chunked")],
                body: Array("5\r\nhello\r\n0\r\n\r\n".utf8),
                sendsContentLength: false
            )
            #expect(chunked.status == 411)
            #expect(directoryEntries(harness.uploads).isEmpty)
        }
    }

    @Test func bodyAboveTwentyMegabytesGets413AndTheLimitItselfIsAccepted() async throws {
        try await withUploadGateway { harness in
            let limit = UploadStore.maxBodySize
            #expect(limit == 20 * 1024 * 1024)

            let above = try await UploadRequests.image(port: harness.port, token: harness.token, body: [UInt8](repeating: 0xAB, count: limit + 1))
            #expect(above.status == 413)
            #expect(directoryEntries(harness.uploads).isEmpty)

            let exact = try await UploadRequests.image(port: harness.port, token: harness.token, body: [UInt8](repeating: 0xAB, count: limit))
            #expect(exact.status == 200)
            let upload = try JSONDecoder().decode(UploadResponse.self, from: exact.body)
            let attributes = try FileManager.default.attributesOfItem(atPath: upload.path)
            #expect((attributes[.size] as? Int) == limit)
        }
    }

    @Test(arguments: [String?.none, "image/gif", "image/jpg", "application/octet-stream", "text/plain", "multipart/form-data; boundary=x"])
    func otherContentTypesGet415(_ contentType: String?) async throws {
        try await withUploadGateway { harness in
            let response = try await UploadRequests.image(port: harness.port, token: harness.token, contentType: contentType, body: UploadSamples.jpeg)
            #expect(response.status == 415)
            #expect(directoryEntries(harness.uploads).isEmpty)
        }
    }

    @Test func emptyBodyGets400() async throws {
        try await withUploadGateway { harness in
            let response = try await UploadRequests.image(port: harness.port, token: harness.token, body: [])
            #expect(response.status == 400)
            #expect(directoryEntries(harness.uploads).isEmpty)
        }
    }

    @Test func authenticationIsCheckedBeforeTheOtherErrors() async throws {
        try await withUploadGateway { harness in
            let response = try await UploadRequests.post(
                port: harness.port,
                headers: [("Content-Type", "text/plain")],
                body: [],
                sendsContentLength: false
            )
            #expect(response.status == 401)
        }
    }

    @Test func clientSuppliedPathsAreIgnored() async throws {
        try await withUploadGateway { harness in
            let escape = harness.hub.directory.appending(path: "fora.jpg").fileSystemPath
            let response = try await UploadRequests.post(
                port: harness.port,
                target: "\(Gateway.uploadPath)?path=\(escape)&name=..%2F..%2Fdevices.json",
                headers: [
                    ("Authorization", "Bearer \(harness.token)"),
                    ("Content-Type", "image/jpeg"),
                    ("Content-Disposition", "attachment; filename=\"../../devices.json\""),
                    ("X-Filename", escape),
                ],
                body: UploadSamples.jpeg
            )

            #expect(response.status == 200)
            let upload = try JSONDecoder().decode(UploadResponse.self, from: response.body)
            let file = URL(filePath: upload.path)
            #expect(file.deletingLastPathComponent().fileSystemPath == harness.uploads.fileSystemPath)
            #expect(isUUIDFileName(file.lastPathComponent, extension: "jpg"))
            #expect(!FileManager.default.fileExists(atPath: escape))
            #expect(try await harness.hub.devices.devices().count == 1)
            #expect(directoryEntries(harness.uploads) == [file.lastPathComponent])
        }
    }

    @Test func gatewayWithoutAnUploadStoreHasNoUploadRoute() async throws {
        try await withHub { hub in
            let gateway = Gateway(version: "9.9.9", herdr: hub.herdr, hub: hub.hub)
            try await withRunningServer(gateway.makeRouter()) { port in
                let response = try await UploadRequests.image(port: port, token: "x", body: UploadSamples.jpeg)
                #expect(response.status == 404)
            }
        }
    }
}
