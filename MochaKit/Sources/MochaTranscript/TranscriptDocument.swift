import Foundation
import MochaProtocol

public struct TranscriptDocument: Sendable, Equatable {
    public var items: [ChatItem]
    public var header: TranscriptHeader
    public var statistics: TranscriptStatistics
    public var pendingByteCount: Int
    public var changes: [TranscriptChange]

    public static func read(path: String) throws(TranscriptFileError) -> TranscriptDocument {
        let file = try TranscriptFile(path: path)
        var accumulator = Accumulator(keepingItems: true)
        try file.forEachAppendedLine { offset, bytes in
            accumulator.consume(TranscriptLineParser.parse(bytes, offset: offset))
        }
        return accumulator.document(pendingByteCount: file.pendingByteCount)
    }

    public static func summary(path: String) throws(TranscriptFileError) -> TranscriptDocument {
        let file = try TranscriptFile(path: path)
        var accumulator = Accumulator(keepingItems: false)
        try file.forEachAppendedLine { offset, bytes in
            accumulator.consume(TranscriptLineParser.parse(bytes, offset: offset))
        }
        return accumulator.document(pendingByteCount: file.pendingByteCount)
    }

    public init(bytes: [UInt8]) {
        var accumulator = Accumulator(keepingItems: true)
        var lineStart = 0
        bytes.withUnsafeBytes { buffer in
            for index in buffer.indices where buffer[index] == 0x0A {
                let line = UnsafeRawBufferPointer(rebasing: buffer[lineStart..<index])
                accumulator.consume(TranscriptLineParser.parse(line, offset: UInt64(lineStart)))
                lineStart = index + 1
            }
        }
        self = accumulator.document(pendingByteCount: bytes.count - lineStart)
    }

    private init(
        items: [ChatItem],
        header: TranscriptHeader,
        statistics: TranscriptStatistics,
        pendingByteCount: Int,
        changes: [TranscriptChange]
    ) {
        self.items = items
        self.header = header
        self.statistics = statistics
        self.pendingByteCount = pendingByteCount
        self.changes = changes
    }

    private struct Accumulator {
        let keepingItems: Bool
        var reducer = TranscriptReducer()
        var header = TranscriptHeader()
        var list = ChatItemList()
        var changes: [TranscriptChange] = []

        init(keepingItems: Bool) {
            self.keepingItems = keepingItems
        }

        mutating func consume(_ line: ParsedLine) {
            header.absorb(line)
            let lineChanges = reducer.apply(line)
            guard keepingItems else { return }
            for change in lineChanges {
                list.apply(change)
            }
            changes.append(contentsOf: lineChanges)
        }

        func document(pendingByteCount: Int) -> TranscriptDocument {
            TranscriptDocument(
                items: list.items,
                header: header,
                statistics: reducer.statistics,
                pendingByteCount: pendingByteCount,
                changes: changes
            )
        }
    }
}
