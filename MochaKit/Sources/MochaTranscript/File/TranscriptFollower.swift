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
    private let mode: TranscriptParseMode
    private var reducer = TranscriptReducer()
    private var home = TranscriptHomeTracker()
    private var seedCache: ParsedLineCache
    private var parser: SequentialLineParser
    public private(set) var header: TranscriptHeader
    public var imageStore: TranscriptImageStore? {
        didSet {
            parser.imageStore = imageStore
            seedCache.imageStore = imageStore
        }
    }

    public init(
        path: String,
        start: Start,
        mode: TranscriptParseMode = .main,
        imageStore: TranscriptImageStore? = nil
    ) throws(TranscriptFileError) {
        file = try TranscriptFile(path: path)
        self.mode = mode
        self.imageStore = imageStore
        seedCache = ParsedLineCache(mode: mode, imageStore: imageStore)
        parser = SequentialLineParser(mode, imageStore: imageStore)
        header = TranscriptHeader()
        guard case .afterExistingLines = start else { return }
        try file.indexToEnd()
        let seedStart = max(0, file.lineCount - Self.seedLines)
        for index in seedStart..<file.lineCount {
            home.absorb(reducer.apply(try seedCache.line(index, in: file)))
        }
        parser = SequentialLineParser(resuming: try seedCache.mode(forLine: file.lineCount, in: file), imageStore: imageStore)
        let scanned = try TranscriptHeaderScanner.scan(file, end: file.indexedEnd, mode: mode)
        header = scanned.header
        home.seed(olderActivity: scanned.activity)
        home.apply(to: &header)
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
        var cache = ParsedLineCache(mode: mode, imageStore: imageStore)
        return try TranscriptPager(file: file).page(endingBefore: line, limit: limit, cache: &cache)
    }

    public func readAppendedLines() throws(TranscriptFileError) -> TranscriptFollowUpdate {
        var update = TranscriptFollowUpdate()
        for line in try file.readAppendedLines() {
            let parsed = parser.parse(line.bytes, offset: line.offset)
            header.absorb(parsed)
            let changes = reducer.apply(parsed)
            home.absorb(changes)
            update.changes.append(contentsOf: changes)
            update.unknownNames.formUnion(parsed.unknownNames)
            update.lineCount += 1
        }
        home.apply(to: &header)
        return update
    }
}

public final class TranscriptPageReader {
    private let file: TranscriptFile
    private let mode: TranscriptParseMode
    private let imageStore: TranscriptImageStore?

    public init(path: String, mode: TranscriptParseMode = .main, imageStore: TranscriptImageStore? = nil) throws(TranscriptFileError) {
        file = try TranscriptFile(path: path)
        self.mode = mode
        self.imageStore = imageStore
        try file.indexToEnd()
    }

    public func lastPage(limit: Int) throws(TranscriptFileError) -> TranscriptPageSlice {
        var cache = ParsedLineCache(mode: mode, imageStore: imageStore)
        return try TranscriptPager(file: file).page(endingBefore: file.lineCount, limit: limit, cache: &cache)
    }

    public func page(beforeOffset offset: UInt64, limit: Int) throws(TranscriptFileError) -> TranscriptPageSlice? {
        guard let line = file.lineIndex(forOffset: offset) else { return nil }
        var cache = ParsedLineCache(mode: mode, imageStore: imageStore)
        return try TranscriptPager(file: file).page(endingBefore: line, limit: limit, cache: &cache)
    }

    public var lineOffsets: [UInt64] {
        file.lineOffsets
    }
}
