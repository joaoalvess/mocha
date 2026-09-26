import Foundation
import MochaProtocol

public struct TranscriptFollowUpdate: Sendable, Equatable {
    public var changes: [TranscriptChange]
    public var unknownNames: Set<String>
    public var lineCount: Int

    public init(changes: [TranscriptChange] = [], unknownNames: Set<String> = [], lineCount: Int = 0) {
        self.changes = changes
        self.unknownNames = unknownNames
        self.lineCount = lineCount
    }
}

public final class TranscriptFollower {
    public enum Start: Sendable {
        case afterExistingLines
        case beginningOfFile
    }

    static let seedLines = 256

    private let file: TranscriptFile
    private var reducer = TranscriptReducer()
    private var seedCache = ParsedLineCache()
    public private(set) var header: TranscriptHeader

    public init(path: String, start: Start) throws(TranscriptFileError) {
        file = try TranscriptFile(path: path)
        header = TranscriptHeader()
        guard case .afterExistingLines = start else { return }
        try file.indexToEnd()
        let seedStart = max(0, file.lineCount - Self.seedLines)
        for index in seedStart..<file.lineCount {
            _ = reducer.apply(try seedCache.line(index, in: file))
        }
        header = try TranscriptHeaderScanner.scan(file, end: file.indexedEnd)
    }

    public var path: String {
        file.path
    }

    public var endOffset: UInt64 {
        file.indexedEnd
    }

    public var lineCount: Int {
        file.lineCount
    }

    public var pendingByteCount: Int {
        file.pendingByteCount
    }

    public func status() -> TranscriptFileStatus? {
        file.status()
    }

    public func lastPage(limit: Int) throws(TranscriptFileError) -> TranscriptPageSlice {
        defer { seedCache.removeAll() }
        return try TranscriptPager(file: file).page(endingBefore: file.lineCount, limit: limit, cache: &seedCache)
    }

    public func page(beforeOffset offset: UInt64, limit: Int) throws(TranscriptFileError) -> TranscriptPageSlice? {
        guard let line = file.lineIndex(forOffset: offset) else { return nil }
        var cache = ParsedLineCache()
        return try TranscriptPager(file: file).page(endingBefore: line, limit: limit, cache: &cache)
    }

    public func readAppendedLines() throws(TranscriptFileError) -> TranscriptFollowUpdate {
        var update = TranscriptFollowUpdate()
        for line in try file.readAppendedLines() {
            let parsed = TranscriptLineParser.parse(line.bytes, offset: line.offset)
            header.absorb(parsed)
            update.changes.append(contentsOf: reducer.apply(parsed))
            update.unknownNames.formUnion(parsed.unknownNames)
            update.lineCount += 1
        }
        return update
    }
}

public final class TranscriptPageReader {
    private let file: TranscriptFile

    public init(path: String) throws(TranscriptFileError) {
        file = try TranscriptFile(path: path)
        try file.indexToEnd()
    }

    public func lastPage(limit: Int) throws(TranscriptFileError) -> TranscriptPageSlice {
        var cache = ParsedLineCache()
        return try TranscriptPager(file: file).page(endingBefore: file.lineCount, limit: limit, cache: &cache)
    }

    public func page(beforeOffset offset: UInt64, limit: Int) throws(TranscriptFileError) -> TranscriptPageSlice? {
        guard let line = file.lineIndex(forOffset: offset) else { return nil }
        var cache = ParsedLineCache()
        return try TranscriptPager(file: file).page(endingBefore: line, limit: limit, cache: &cache)
    }

    public var lineOffsets: [UInt64] {
        file.lineOffsets
    }
}
