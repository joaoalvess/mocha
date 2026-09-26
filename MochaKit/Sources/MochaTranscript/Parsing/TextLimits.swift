import Foundation

enum TextLimits {
    static let summary = 120
    static let inputJSON = 4_000
    static let resultPreview = 2_000
}

extension String {
    func truncated(toCharacters limit: Int) -> String {
        guard utf8.count > limit else { return self }
        guard let end = index(startIndex, offsetBy: limit, limitedBy: endIndex) else { return self }
        return String(self[..<end])
    }

    var firstNonEmptyLine: String {
        for line in split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    func trimmingNewlines() -> String {
        var scalars = Substring(self)
        while let first = scalars.first, first.isNewline { scalars.removeFirst() }
        while let last = scalars.last, last.isNewline { scalars.removeLast() }
        return String(scalars)
    }

    var isBlank: Bool {
        allSatisfy(\.isWhitespace)
    }
}
