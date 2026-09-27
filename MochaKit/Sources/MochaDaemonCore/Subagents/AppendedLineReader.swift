import Foundation
import MochaTranscript

struct AppendedLineReader: Sendable {
    struct Batch: Sendable {
        var lines: [[UInt8]] = []
        var restarted = false
    }

    private(set) var offset: UInt64
    private var inode: UInt64?
    private var skipsPartialFirstLine: Bool

    init(offset: UInt64 = 0, skipsPartialFirstLine: Bool = false) {
        self.offset = offset
        self.skipsPartialFirstLine = skipsPartialFirstLine
    }

    static func tail(of path: String, limit: UInt64) -> AppendedLineReader {
        guard let size = TranscriptFileStatus.of(path: path)?.size, size > limit else { return AppendedLineReader() }
        return AppendedLineReader(offset: size - limit, skipsPartialFirstLine: true)
    }

    mutating func read(path: String, bytesRead: (Int) -> Void) -> Batch {
        var batch = Batch()
        guard let status = TranscriptFileStatus.of(path: path) else { return batch }
        if let inode, inode != status.inode || status.size < offset {
            offset = 0
            skipsPartialFirstLine = false
            batch.restarted = true
        }
        inode = status.inode
        guard status.size > offset, let handle = FileHandle(forReadingAtPath: path) else { return batch }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: Int(status.size - offset)) else {
            return batch
        }
        bytesRead(data.count)
        var bytes = [UInt8](data)
        guard let lastNewline = bytes.lastIndex(of: 0x0A) else { return batch }
        bytes.removeSubrange((lastNewline + 1)...)
        offset += UInt64(bytes.count)
        var lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: true).map(Array.init)
        if skipsPartialFirstLine {
            skipsPartialFirstLine = false
            if bytes.first != 0x0A, !lines.isEmpty {
                lines.removeFirst()
            }
        }
        batch.lines = lines
        return batch
    }
}
