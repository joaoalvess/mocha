enum DemoImageMarkers {
    private static let opening = "[imagem: "
    private static let prefix = opening + "/"
    private static let suffix = "]"
    private static let uploadsComponent = "/Library/Application Support/Mocha/uploads/"

    static func split(_ text: String) -> (text: String, imageCount: Int, imagePaths: [String]) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let imagePaths = lines.compactMap(imagePath)
        guard !imagePaths.isEmpty else { return (text, 0, []) }
        var kept = lines.filter { imagePath($0) == nil }
        while kept.last?.allSatisfy(\.isWhitespace) == true {
            kept.removeLast()
        }
        return (kept.joined(separator: "\n"), imagePaths.count, imagePaths)
    }

    private static func imagePath(_ line: Substring) -> String? {
        guard line.contains(uploadsComponent) else { return nil }
        if line.hasPrefix(prefix), line.hasSuffix(suffix) {
            return String(line.dropFirst(opening.count).dropLast(suffix.count))
        }
        return line.hasPrefix("/") ? String(line) : nil
    }
}
