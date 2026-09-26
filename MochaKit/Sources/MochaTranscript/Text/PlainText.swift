import Foundation

public enum PlainText {
    public static let previewLimit = 200

    public static func preview(fromMarkdown markdown: String, limit: Int = previewLimit) -> String {
        var output = CollapsedText(limit: max(limit, 0))
        var fence: Fence?
        for line in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            guard !output.isFull else { break }
            if let open = fence {
                if open.isClosed(by: line) {
                    fence = nil
                } else {
                    output.append(line)
                }
                output.appendBreak()
                continue
            }
            if let opening = Fence(opening: line) {
                fence = opening
                output.appendBreak()
                continue
            }
            InlineMarkdown(Array(withoutBlockMarkers(line))).write(to: &output)
            output.appendBreak()
        }
        return output.text
    }

    private static func withoutBlockMarkers(_ line: Substring) -> Substring {
        var rest = line.drop(while: \.isWhitespace)
        while rest.first == ">" {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        rest = withoutHeadingMarker(rest)
        return withoutListMarker(rest)
    }

    private static func withoutHeadingMarker(_ line: Substring) -> Substring {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return line }
        let rest = line.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return line }
        return rest.drop(while: \.isWhitespace)
    }

    private static func withoutListMarker(_ line: Substring) -> Substring {
        if let first = line.first, "-*+".contains(first) {
            let rest = line.dropFirst()
            guard rest.first?.isWhitespace == true else { return line }
            return rest.drop(while: \.isWhitespace)
        }
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...9).contains(digits.count) else { return line }
        let afterDigits = line.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return line }
        let rest = afterDigits.dropFirst()
        guard rest.first?.isWhitespace == true else { return line }
        return rest.drop(while: \.isWhitespace)
    }
}

private struct Fence {
    let marker: Character
    let length: Int

    init?(opening line: Substring) {
        let trimmed = line.drop(while: \.isWhitespace)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first })
        guard run.count >= 3 else { return nil }
        if first == "`", trimmed.dropFirst(run.count).contains("`") { return nil }
        marker = first
        length = run.count
    }

    func isClosed(by line: Substring) -> Bool {
        let trimmed = line.drop(while: \.isWhitespace)
        let run = trimmed.prefix(while: { $0 == marker })
        return run.count >= length && trimmed.dropFirst(run.count).allSatisfy(\.isWhitespace)
    }
}

private struct CollapsedText {
    let limit: Int
    private(set) var characters: [Character] = []
    private var pendingSpace = false

    init(limit: Int) {
        self.limit = limit
    }

    var isFull: Bool {
        characters.count >= limit
    }

    var text: String {
        var kept = characters.prefix(limit)
        while kept.last?.isWhitespace == true {
            kept.removeLast()
        }
        return String(kept)
    }

    mutating func append(_ character: Character) {
        guard !isFull else { return }
        if character.isWhitespace {
            pendingSpace = !characters.isEmpty
            return
        }
        if pendingSpace {
            characters.append(" ")
            pendingSpace = false
            guard !isFull else { return }
        }
        characters.append(character)
    }

    mutating func append(_ text: some StringProtocol) {
        for character in text {
            guard !isFull else { return }
            append(character)
        }
    }

    mutating func appendBreak() {
        append(" ")
    }
}

private struct InlineMarkdown {
    private let characters: [Character]

    init(_ characters: [Character]) {
        self.characters = characters
    }

    func write(to output: inout CollapsedText) {
        var index = 0
        while index < characters.count, !output.isFull {
            let character = characters[index]
            switch character {
            case "\\" where index + 1 < characters.count && isEscapable(characters[index + 1]):
                output.append(characters[index + 1])
                index += 2
            case "`":
                index = writeCode(from: index, to: &output)
            case "!" where index + 1 < characters.count && characters[index + 1] == "[":
                if let link = link(at: index + 1) {
                    InlineMarkdown(Array(characters[link.text])).write(to: &output)
                    index = link.end
                } else {
                    output.append(character)
                    index += 1
                }
            case "[":
                if let link = link(at: index) {
                    InlineMarkdown(Array(characters[link.text])).write(to: &output)
                    index = link.end
                } else {
                    output.append(character)
                    index += 1
                }
            case "*", "_", "~":
                index = writeEmphasisRun(from: index, to: &output)
            default:
                output.append(character)
                index += 1
            }
        }
    }

    private func isEscapable(_ character: Character) -> Bool {
        character.isASCII && (character.isPunctuation || character.isSymbol)
    }

    private func runLength(of marker: Character, from start: Int) -> Int {
        var end = start
        while end < characters.count, characters[end] == marker { end += 1 }
        return end - start
    }

    private func writeCode(from start: Int, to output: inout CollapsedText) -> Int {
        let length = runLength(of: "`", from: start)
        var search = start + length
        while search < characters.count {
            if characters[search] == "`" {
                let closing = runLength(of: "`", from: search)
                if closing == length {
                    output.append(String(characters[(start + length)..<search]))
                    return search + closing
                }
                search += closing
            } else {
                search += 1
            }
        }
        return start + length
    }

    private func writeEmphasisRun(from start: Int, to output: inout CollapsedText) -> Int {
        let marker = characters[start]
        let length = runLength(of: marker, from: start)
        let end = start + length
        let before = start > 0 ? characters[start - 1] : nil
        let after = end < characters.count ? characters[end] : nil
        if isEmphasisDelimiter(marker, length: length, before: before, after: after) {
            return end
        }
        output.append(String(characters[start..<end]))
        return end
    }

    private func isEmphasisDelimiter(_ marker: Character, length: Int, before: Character?, after: Character?) -> Bool {
        switch marker {
        case "~":
            return length >= 2
        case "_":
            return !(isWordCharacter(before) && isWordCharacter(after))
        default:
            return !(isSpaceOrEdge(before) && isSpaceOrEdge(after))
        }
    }

    private func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }

    private func isSpaceOrEdge(_ character: Character?) -> Bool {
        character?.isWhitespace ?? true
    }

    private func link(at open: Int) -> (text: Range<Int>, end: Int)? {
        guard let close = matching("[", "]", from: open), close + 1 < characters.count, characters[close + 1] == "(" else {
            return nil
        }
        guard let urlEnd = matching("(", ")", from: close + 1) else { return nil }
        return ((open + 1)..<close, urlEnd + 1)
    }

    private func matching(_ opening: Character, _ closing: Character, from start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }
}
