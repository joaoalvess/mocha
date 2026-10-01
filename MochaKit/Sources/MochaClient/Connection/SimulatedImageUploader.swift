import Foundation
import MochaProtocol

public struct SimulatedImageUploader: ImageUploading {
    public static let uploadsDirectory = "/Users/demo/Library/Application Support/Mocha/uploads"
    public static let delay: Duration = .milliseconds(400)

    private let uploadsDirectory: String
    private let delay: Duration
    private let library: SimulatedImageLibrary?

    public init(
        uploadsDirectory: String = SimulatedImageUploader.uploadsDirectory,
        delay: Duration = SimulatedImageUploader.delay,
        library: SimulatedImageLibrary? = nil
    ) {
        self.uploadsDirectory = uploadsDirectory
        self.delay = delay
        self.library = library
    }

    public func upload(_ image: PromptImage) async throws(ImageUploadError) -> UploadResponse {
        guard !image.data.isEmpty else { throw .emptyBody }
        do {
            try await Task.sleep(for: delay)
        } catch {
            throw .network
        }
        let name = UUID().uuidString.lowercased() + "." + image.contentType.fileExtension
        let path = uploadsDirectory + "/" + name
        await library?.store(image.data, at: path)
        return UploadResponse(path: path)
    }
}
