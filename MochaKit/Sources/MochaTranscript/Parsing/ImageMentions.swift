import Foundation

enum ImageMentions {
    static let limit = 6

    private static let extensionBytes: [[UInt8]] = ImageFileExtension.all.sorted().map { Array($0.utf8) }

    static func paths(in markdown: String, cwd: String?, home: String) -> [String] {
        guard mayMentionImage(markdown) else { return [] }
        var paths: [String] = []
        for line in linesOutsideFences(markdown) where mayMentionImage(String(line)) {
            var scanner = CandidateScanner(characters: Array(line))
            scanner.scanAll()
            for candidate in scanner.candidates {
                guard let path = resolve(candidate, cwd: cwd, home: home), !paths.contains(path) else { continue }
                paths.append(path)
                if paths.count == limit { return paths }
            }
        }
        return paths
    }

    static func mayMentionImage(_ text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            bytes.indices.contains { bytes[$0] == UInt8(ascii: ".") && hasImageExtension(bytes, afterDotAt: $0) }
        }
    }

    private static func hasImageExtension(_ bytes: UnsafeBufferPointer<UInt8>, afterDotAt dot: Int) -> Bool {
        extensionBytes.contains { pattern in
            guard dot + pattern.count < bytes.count else { return false }
            return pattern.indices.allSatisfy { bytes[dot + 1 + $0] | 0x20 == pattern[$0] }
        }
    }

    private static func resolve(_ candidate: String, cwd: String?, home: String) -> String? {
        let absolute: String
        if candidate.hasPrefix("/") {
            absolute = candidate
        } else if candidate.hasPrefix("~/") {
            guard home.hasPrefix("/") else { return nil }
            absolute = joined(home, candidate.dropFirst(2))
        } else if let cwd, cwd.hasPrefix("/") {
            absolute = joined(cwd, candidate)
        } else {
            return nil
        }
        return URL(filePath: absolute).standardized.path(percentEncoded: false)
    }

    private static func joined(_ directory: String, _ relative: some StringProtocol) -> String {
        var base = directory
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base + "/" + relative
    }

    private static func linesOutsideFences(_ markdown: String) -> [Substring] {
        var lines: [Substring] = []
        var fence: CodeFence?
        for line in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let open = fence {
                if open.isClosed(by: line) {
                    fence = nil
                }
                continue
            }
            if let opening = CodeFence(opening: line) {
                fence = opening
                continue
            }
            lines.append(line)
        }
        return lines
    }
}

private struct CodeFence {
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

private struct CandidateScanner {
    private static let leadingPunctuation: Set<Character> = ["(", "\"", "'", "*"]
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "\"", "'", "*"]

    let characters: [Character]
    private(set) var candidates: [String] = []

    init(characters: [Character]) {
        self.characters = characters
    }

    mutating func scanAll() {
        scan(characters.indices)
    }

    private mutating func scan(_ range: Range<Int>) {
        var tokenStart: Int?
        var index = range.lowerBound
        while index < range.upperBound {
            let character = characters[index]
            if character.isWhitespace {
                addToken(from: &tokenStart, to: index)
                index += 1
            } else if character == "`" {
                let length = runLength(of: "`", from: index, limit: range.upperBound)
                if let close = closingRun(length: length, from: index + length, limit: range.upperBound) {
                    addToken(from: &tokenStart, to: index)
                    add(String(characters[(index + length)..<close]).trimmingCharacters(in: .whitespaces))
                    index = close + length
                } else {
                    tokenStart = tokenStart ?? index
                    index += length
                }
            } else if character == "[", let link = link(openingAt: index, limit: range.upperBound) {
                addToken(from: &tokenStart, to: index)
                scan(link.text)
                add(link.destination)
                index = link.end
            } else {
                tokenStart = tokenStart ?? index
                index += 1
            }
        }
        addToken(from: &tokenStart, to: range.upperBound)
    }

    private mutating func addToken(from start: inout Int?, to end: Int) {
        guard let tokenStart = start else { return }
        start = nil
        let token = characters[tokenStart..<end]
        guard token.contains(".") else { return }
        add(String(token))
    }

    private mutating func add(_ raw: String) {
        var candidate = Substring(raw)
        while let first = candidate.first, Self.leadingPunctuation.contains(first) {
            candidate.removeFirst()
        }
        while let last = candidate.last, Self.trailingPunctuation.contains(last) {
            candidate.removeLast()
        }
        guard !candidate.isEmpty, !candidate.contains("://"), ImageFileExtension.matches(candidate) else { return }
        candidates.append(String(candidate))
    }

    private func runLength(of marker: Character, from start: Int, limit: Int) -> Int {
        var end = start
        while end < limit, characters[end] == marker {
            end += 1
        }
        return end - start
    }

    private func closingRun(length: Int, from start: Int, limit: Int) -> Int? {
        var index = start
        while index < limit {
            guard characters[index] == "`" else {
                index += 1
                continue
            }
            let run = runLength(of: "`", from: index, limit: limit)
            if run == length { return index }
            index += run
        }
        return nil
    }

    private func link(openingAt open: Int, limit: Int) -> (text: Range<Int>, destination: String, end: Int)? {
        guard let close = matching("[", "]", from: open, limit: limit),
              close + 1 < limit,
              characters[close + 1] == "(",
              let end = matching("(", ")", from: close + 1, limit: limit) else {
            return nil
        }
        let inside = String(characters[(close + 2)..<end]).trimmingCharacters(in: .whitespaces)
        return ((open + 1)..<close, Self.destination(inside), end + 1)
    }

    private static func destination(_ inside: String) -> String {
        if inside.hasPrefix("<"), let end = inside.firstIndex(of: ">") {
            return String(inside[inside.index(after: inside.startIndex)..<end])
        }
        return String(inside.prefix { !$0.isWhitespace })
    }

    private func matching(_ opening: Character, _ closing: Character, from start: Int, limit: Int) -> Int? {
        var depth = 0
        var index = start
        while index < limit {
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
