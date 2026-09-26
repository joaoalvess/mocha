public struct ImagePromptUploadFailure: Error, Sendable, Equatable {
    public let imageIndex: Int
    public let error: ImageUploadError
}

public enum ImagePromptSender {
    public static func send(
        text: String,
        images: [PromptImage],
        uploader: any ImageUploading,
        sendPrompt: @Sendable (String) async throws -> Void
    ) async throws {
        var paths: [String] = []
        for (index, image) in images.enumerated() {
            do {
                paths.append(try await uploader.upload(image).path)
            } catch {
                throw ImagePromptUploadFailure(imageIndex: index, error: error)
            }
        }
        try await sendPrompt(PromptImages.promptText(text, imagePaths: paths))
    }
}
