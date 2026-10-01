import Foundation

enum PastedContent {
    static func unwrapped(_ text: String) -> String {
        guard text.contains("pasted_content") else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { !isTagLine($0) }
        guard kept.count < lines.count else { return text }
        return kept.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static func isTagLine(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespaces).wholeMatch(of: /<\/?pasted_content\b[^>]*>/) != nil
    }
}
