enum DemoImageMarkers {
    private static let prefix = "[imagem: /"
    private static let suffix = "]"
    private static let uploadsComponent = "/Library/Application Support/Mocha/uploads/"

    static func split(_ text: String) -> (text: String, imageCount: Int) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var kept = lines.filter { !isMarker($0) }
        let imageCount = lines.count - kept.count
        guard imageCount > 0 else { return (text, 0) }
        while kept.last?.allSatisfy(\.isWhitespace) == true {
            kept.removeLast()
        }
        return (kept.joined(separator: "\n"), imageCount)
    }

    private static func isMarker(_ line: Substring) -> Bool {
        line.hasPrefix(prefix) && line.hasSuffix(suffix) && line.contains(uploadsComponent)
    }
}
