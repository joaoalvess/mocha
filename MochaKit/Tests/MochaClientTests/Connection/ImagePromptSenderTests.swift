import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaClient

actor ScriptedUploader: ImageUploading {
    private let failingIndex: Int?
    private(set) var uploaded: [PromptImage] = []

    init(failingAt failingIndex: Int? = nil) {
        self.failingIndex = failingIndex
    }

    func upload(_ image: PromptImage) async throws(ImageUploadError) -> UploadResponse {
        if uploaded.count == failingIndex {
            throw .payloadTooLarge
        }
        uploaded.append(image)
        return UploadResponse(path: "/Users/joao/Library/Application Support/Mocha/uploads/\(uploaded.count).jpg")
    }
}

final class PromptRecorder: Sendable {
    private let prompts = Mutex<[String]>([])

    var sent: [String] {
        prompts.withLock { $0 }
    }

    func record(_ prompt: String) {
        prompts.withLock { $0.append(prompt) }
    }
}

struct ImagePromptSenderTests {
    private static let images = (1...3).map { PromptImage(data: Data([UInt8($0)]), contentType: .jpeg) }
    private static let uploads = "/Users/joao/Library/Application Support/Mocha/uploads"

    @Test func uploadsInOrderThenSendsOnePromptWithThePaths() async throws {
        let uploader = ScriptedUploader()
        let recorder = PromptRecorder()
        try await ImagePromptSender.send(text: "compara as telas", images: Self.images, uploader: uploader) { prompt in
            recorder.record(prompt)
        }
        #expect(await uploader.uploaded == Self.images)
        #expect(recorder.sent == [
            """
            compara as telas
            \(Self.uploads)/1.jpg
            \(Self.uploads)/2.jpg
            \(Self.uploads)/3.jpg
            """,
        ])
    }

    @Test func uploadedPathsArriveBeforeThePromptIsSent() async throws {
        let uploader = ScriptedUploader()
        let recorder = PromptRecorder()
        try await ImagePromptSender.send(
            text: "olha",
            images: Array(Self.images.prefix(2)),
            uploader: uploader,
            onUploaded: { paths in recorder.record("uploaded " + paths.joined(separator: ",")) }
        ) { prompt in
            recorder.record(prompt)
        }
        #expect(recorder.sent == [
            "uploaded \(Self.uploads)/1.jpg,\(Self.uploads)/2.jpg",
            "olha\n\(Self.uploads)/1.jpg\n\(Self.uploads)/2.jpg",
        ])
    }

    @Test func failedUploadNeverReportsPaths() async throws {
        let uploader = ScriptedUploader(failingAt: 0)
        let recorder = PromptRecorder()
        await #expect(throws: ImagePromptUploadFailure.self) {
            try await ImagePromptSender.send(
                text: "olha",
                images: Self.images,
                uploader: uploader,
                onUploaded: { _ in recorder.record("uploaded") }
            ) { prompt in
                recorder.record(prompt)
            }
        }
        #expect(recorder.sent.isEmpty)
    }

    @Test func failedUploadStopsTheRestAndNeverSendsThePrompt() async throws {
        let uploader = ScriptedUploader(failingAt: 1)
        let recorder = PromptRecorder()
        await #expect(throws: ImagePromptUploadFailure(imageIndex: 1, error: .payloadTooLarge)) {
            try await ImagePromptSender.send(text: "compara", images: Self.images, uploader: uploader) { prompt in
                recorder.record(prompt)
            }
        }
        #expect(await uploader.uploaded == [Self.images[0]])
        #expect(recorder.sent.isEmpty)
    }

    @Test func promptFailureIsRethrownAfterTheUploads() async throws {
        let uploader = ScriptedUploader()
        await #expect(throws: ServerConnectionError.notConnected) {
            try await ImagePromptSender.send(text: "", images: [Self.images[0]], uploader: uploader) { _ in
                throw ServerConnectionError.notConnected
            }
        }
        #expect(await uploader.uploaded.count == 1)
    }
}
