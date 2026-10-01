enum DemoImageMarkers {
    private static let opening = "[imagem: "
    private static let prefix = opening + "/"
    private static let suffix = "]"
    private static let uploadsComponent = "/Library/Application Support/Mocha/uploads/"

    static func split(_ text: String) -> (text: String, imageCount: Int, imagePaths: [String]) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let imagePaths = lines.filter(isMarker).map { String($0.dropFirst(opening.count).dropLast(suffix.count)) }
        guard !imagePaths.isEmpty else { return (text, 0, []) }
        var kept = lines.filter { !isMarker($0) }
        while kept.last?.allSatisfy(\.isWhitespace) == true {
            kept.removeLast()
        }
        return (kept.joined(separator: "\n"), imagePaths.count, imagePaths)
    }

    private static func isMarker(_ line: Substring) -> Bool {
        line.hasPrefix(prefix) && line.hasSuffix(suffix) && line.contains(uploadsComponent)
    }
}
