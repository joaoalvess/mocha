import Foundation

enum ImagePasteChips {
    static func removing(ids: [Int], from text: String) -> String {
        guard !ids.isEmpty, text.contains("[Image #") else { return text }
        let pasted = Set(ids)
        var removed = false
        let kept = text.replacing(/\[Image #(\d+)\] ?/) { match -> String in
            guard let id = Int(match.output.1), pasted.contains(id) else { return String(match.output.0) }
            removed = true
            return ""
        }
        return removed ? kept.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }
}
