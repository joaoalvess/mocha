public enum ImageFileExtension {
    public static let all: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"]

    public static func matches(_ path: some StringProtocol) -> Bool {
        guard let dot = path.lastIndex(of: ".") else { return false }
        let stem = path[..<dot]
        guard let last = stem.last, last != "/" else { return false }
        let pathExtension = path[path.index(after: dot)...]
        guard !pathExtension.contains("/") else { return false }
        return all.contains(pathExtension.lowercased())
    }
}
