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

    struct Extraction: Equatable {
        let text: String
        let paths: [String]

        var count: Int {
            paths.count
        }
    }

    static func extract(from text: String, uploadsDirectory: String = ImageMarkers.uploadsDirectory) -> Extraction {
        guard text.contains(prefix) || text.contains(uploadsDirectory) else { return Extraction(text: text, paths: []) }
        var kept: [Substring] = []
        var paths: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let path = markerPath(line, uploadsDirectory: uploadsDirectory) {
                paths.append(String(path))
            } else {
                kept.append(line)
            }
        }
        guard !paths.isEmpty else { return Extraction(text: text, paths: []) }
        while kept.last?.isEmpty == true {
            kept.removeLast()
        }
        return Extraction(text: kept.joined(separator: "\n"), paths: paths)
    }

    private static func markerPath(_ line: Substring, uploadsDirectory: String) -> Substring? {
        let isBracketed = line.hasPrefix(prefix) && line.hasSuffix(suffix)
        let path = isBracketed ? line.dropFirst(prefix.count).dropLast(suffix.count) : line
        guard path.hasPrefix(uploadsDirectory) else { return nil }
        let isInside = path.dropFirst(uploadsDirectory.count)
            .split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        return isInside ? path : nil
    }
}
