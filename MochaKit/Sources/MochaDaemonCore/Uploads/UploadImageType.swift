import Foundation

public enum UploadImageType: String, Sendable, CaseIterable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case heic = "image/heic"

    public init?(contentType: String?) {
        guard let mediaType = contentType?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() else {
            return nil
        }
        self.init(rawValue: mediaType)
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }
}
