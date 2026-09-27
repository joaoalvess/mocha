import Foundation
import MochaProtocol

public struct TranscriptPageSlice: Sendable, Equatable {
    public var items: [ChatItem]
    public var firstLineOffset: UInt64?
    public var hasMore: Bool

    public init(items: [ChatItem], firstLineOffset: UInt64?, hasMore: Bool) {
        self.items = items
        self.firstLineOffset = firstLineOffset
        self.hasMore = hasMore
    }

    public static let empty = TranscriptPageSlice(items: [], firstLineOffset: nil, hasMore: false)
}

struct ParsedLineCache {
    private var lines: [Int: ParsedLine] = [:]
    private var locator: ForkBoundaryLocator

    init(mode: TranscriptParseMode = .main) {
        locator = ForkBoundaryLocator(mode)
    }

    mutating func line(_ index: Int, in file: TranscriptFile) throws(TranscriptFileError) -> ParsedLine {
        if let cached = lines[index] { return cached }
        let mode = try locator.mode(forLine: index, in: file)
        let parsed = TranscriptLineParser.parse(try file.lineBytes(at: index), offset: file.lineOffsets[index], mode: mode)
        lines[index] = parsed
        return parsed
    }

    mutating func mode(forLine index: Int, in file: TranscriptFile) throws(TranscriptFileError) -> LineMode {
        try locator.mode(forLine: index, in: file)
    }

    mutating func removeAll() {
        lines.removeAll()
    }
}

struct TranscriptPager {
    static let contextLines = 64
    static let lookaheadLines = 64

    let file: TranscriptFile

    func page(endingBefore endLine: Int, limit: Int, cache: inout ParsedLineCache) throws(TranscriptFileError) -> TranscriptPageSlice {
        let limit = max(limit, 1)
        var itemCount = 0
        var startLine = endLine
        var line = endLine - 1
        while line >= 0, itemCount < limit {
            let count = try cache.line(line, in: file).itemCount
            if count > 0 {
                itemCount += count
                startLine = line
            }
            line -= 1
        }
        guard itemCount > 0 else { return .empty }
        var hasMore = false
        var probe = startLine - 1
        while probe >= 0 {
            if try cache.line(probe, in: file).itemCount > 0 {
                hasMore = true
                break
            }
            probe -= 1
        }

        var reducer = TranscriptReducer()
        for index in max(0, startLine - Self.contextLines)..<startLine {
            _ = reducer.apply(try cache.line(index, in: file))
        }
        var list = ChatItemList()
        for index in startLine..<endLine {
            for change in reducer.apply(try cache.line(index, in: file)) {
                list.apply(change)
            }
        }
        let lookaheadEnd = min(file.lineCount, endLine + Self.lookaheadLines)
        if endLine < lookaheadEnd {
            for index in endLine..<lookaheadEnd {
                for change in reducer.apply(try cache.line(index, in: file)) {
                    if case .update = change {
                        list.apply(change)
                    }
                }
            }
        }
        return TranscriptPageSlice(items: list.items, firstLineOffset: file.lineOffsets[startLine], hasMore: hasMore)
    }
}
