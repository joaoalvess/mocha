import Foundation

enum ImageMarkers {
    static let uploadsDirectory = uploadsDirectory(home: FileManager.default.homeDirectoryForCurrentUser)

    private static let prefix = "[imagem: "
    private static let suffix = "]"

    static func uploadsDirectory(home: URL) -> String {
        var path = home.path(percentEncoded: false)
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path + "/Library/Application Support/Mocha/uploads/"
    }

    static func extract(from text: String, uploadsDirectory: String = ImageMarkers.uploadsDirectory) -> (text: String, count: Int) {
        guard text.contains(prefix) else { return (text, 0) }
        var kept: [Substring] = []
        var count = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if isMarker(line, uploadsDirectory: uploadsDirectory) {
                count += 1
            } else {
                kept.append(line)
            }
        }
        guard count > 0 else { return (text, 0) }
        while kept.last?.isEmpty == true {
            kept.removeLast()
        }
        return (kept.joined(separator: "\n"), count)
    }

    private static func isMarker(_ line: Substring, uploadsDirectory: String) -> Bool {
        guard line.hasPrefix(prefix), line.hasSuffix(suffix) else { return false }
        let path = line.dropFirst(prefix.count).dropLast(suffix.count)
        guard path.hasPrefix(uploadsDirectory) else { return false }
        return path.dropFirst(uploadsDirectory.count)
            .split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
