import Foundation

public enum PromptImages {
    public static let limit = 5

    public static func promptText(_ text: String, imagePaths: [String]) -> String {
        let markers = imagePaths.map { "\(markerPrefix)\($0)\(markerSuffix)" }
        let lines = text.isEmpty ? markers : [text] + markers
        return lines.joined(separator: "\n")
    }

    public static func attachmentLabel(imageCount: Int) -> String {
        imageCount == 1 ? "📎 1 imagem" : "📎 \(imageCount) imagens"
    }

    public static func bubbleText(_ text: String, imageCount: Int) -> String {
        guard imageCount > 0 else { return text }
        let label = attachmentLabel(imageCount: imageCount)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return label }
        return text + "\n" + label
    }

    private static let markerPrefix = "[imagem: "
    private static let markerSuffix = "]"
}
