import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaDaemonCore
@testable import MochaTranscript

@Suite(.timeLimit(.minutes(1)))
struct UploadRuntimeTests {
    @Test func uploadsDirectoryLivesInTheSupportDirectoryAndMatchesTheMarkerRule() {
        let home = URL(filePath: "/Users/dev", directoryHint: .isDirectory)
        let paths = DaemonPaths(home: home)
        #expect(paths.uploadsDirectory.fileSystemPath == "/Users/dev/Library/Application Support/Mocha/uploads/")
        #expect(paths.uploadsDirectory.fileSystemPath == ImageMarkers.uploadsDirectory(home: home))
        #expect(DaemonPaths().uploadsDirectory.fileSystemPath == ImageMarkers.uploadsDirectory)
    }

    @Test func transcriptImagesLiveInTheUserCaches() {
        let paths = DaemonPaths(home: URL(filePath: "/Users/dev", directoryHint: .isDirectory))
        #expect(paths.transcriptImagesDirectory.fileSystemPath == "/Users/dev/Library/Caches/com.joaoalves.mocha/transcript-images/")
    }

    @Test func runServesUploadsIntoTheSupportDirectoryAndCleansExpiredOnesOnStart() async throws {
        try await withTemporaryHome(short: true) { home in
            let port = try await DaemonRuntimeTests.freePort()
            try home.write(#"{"gatewayPort": \#(port)}"#, to: "Library/Application Support/Mocha/config.json", permissions: 0o600)
            let uploads = home.paths.uploadsDirectory
            try home.write("velho", to: "Library/Application Support/Mocha/uploads/velho.jpg", permissions: 0o600)
            try home.write("recente", to: "Library/Application Support/Mocha/uploads/recente.png", permissions: 0o600)
            try setModificationDate(Date().addingTimeInterval(-8 * 24 * 60 * 60), of: uploads.appending(path: "velho.jpg"))
            try setModificationDate(Date().addingTimeInterval(-6 * 24 * 60 * 60), of: uploads.appending(path: "recente.png"))
            let token = SecureToken.generate()
            _ = try await DeviceStore(fileURL: home.paths.devicesFile).register(name: "iPhone do João", token: token, at: Date())
            let runtime = DaemonRuntime(options: DaemonRuntimeTests.options(home, herdrSocket: FakeHerdrServer.temporarySocketPath()))

            _ = try await runtime.start()

            #expect(directoryEntries(uploads) == ["recente.png"])
            let response = try await UploadRequests.image(port: port, token: token, contentType: "image/heic", body: UploadSamples.heic)
            #expect(response.status == 200)
            let upload = try JSONDecoder().decode(UploadResponse.self, from: response.body)
            #expect(upload.path.hasPrefix(uploads.fileSystemPath))
            #expect(isUUIDFileName(URL(filePath: upload.path).lastPathComponent, extension: "heic"))
            #expect(fileMode(uploads) == 0o700)
            #expect(try await UploadRequests.image(port: port, token: SecureToken.generate(), body: UploadSamples.jpeg).status == 401)

            await runtime.stop()
        }
    }
}
