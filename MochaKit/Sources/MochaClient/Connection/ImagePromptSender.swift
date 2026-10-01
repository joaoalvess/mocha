public struct ImagePromptUploadFailure: Error, Sendable, Equatable {
    public let imageIndex: Int
    public let error: ImageUploadError
}

public enum ImagePromptSender {
    public static func send(
        text: String,
        images: [PromptImage],
        uploader: any ImageUploading,
        onUploaded: @Sendable ([String]) async -> Void = { _ in },
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
        await onUploaded(paths)
        try await sendPrompt(PromptImages.promptText(text, imagePaths: paths))
    }
}
