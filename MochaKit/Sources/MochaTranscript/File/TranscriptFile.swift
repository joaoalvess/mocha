import Darwin
import Foundation

public enum TranscriptFileError: Error, Sendable, Equatable {
    case notFound
    case system(errno: Int32)
}

public struct TranscriptFileStatus: Sendable, Equatable {
    public var size: UInt64
    public var modificationDate: Date
    public var device: UInt64
    public var inode: UInt64
    public var linkCount: UInt64

    init(_ info: stat) {
        size = UInt64(max(info.st_size, 0))
        modificationDate = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        device = UInt64(bitPattern: Int64(info.st_dev))
        inode = UInt64(info.st_ino)
        linkCount = UInt64(info.st_nlink)
    }

    public static func of(path: String) -> TranscriptFileStatus? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return TranscriptFileStatus(info)
    }

    public func isSameFile(as other: TranscriptFileStatus) -> Bool {
        device == other.device && inode == other.inode
    }
}

struct RawLine {
    let offset: UInt64
    let bytes: [UInt8]
}

final class TranscriptFile {
    private static let chunkSize = 1 << 20

    let path: String
    private let descriptor: Int32
    private(set) var lineOffsets: [UInt64] = []
    private(set) var indexedEnd: UInt64 = 0
    private var pending: [UInt8] = []

    init(path: String) throws(TranscriptFileError) {
        self.path = path
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            throw code == ENOENT ? .notFound : .system(errno: code)
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    var lineCount: Int {
        lineOffsets.count
    }

    var pendingByteCount: Int {
        pending.count
    }

    func status() -> TranscriptFileStatus? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return TranscriptFileStatus(info)
    }

    func indexToEnd() throws(TranscriptFileError) {
        try consumeAppended(keepingLines: false) { _, _ in }
    }

    func readAppendedLines() throws(TranscriptFileError) -> [RawLine] {
        var lines: [RawLine] = []
        try consumeAppended(keepingLines: true) { offset, bytes in
            lines.append(RawLine(offset: offset, bytes: Array(bytes)))
        }
        return lines
    }

    func forEachAppendedLine(_ body: (UInt64, UnsafeRawBufferPointer) -> Void) throws(TranscriptFileError) {
        try consumeAppended(keepingLines: true, body)
    }

    func lineBytes(at index: Int) throws(TranscriptFileError) -> [UInt8] {
        let start = lineOffsets[index]
        let next = index + 1 < lineOffsets.count ? lineOffsets[index + 1] : indexedEnd
        return try read(at: start, count: Int(next - start) - 1)
    }

    func lineIndex(forOffset offset: UInt64) -> Int? {
        var low = 0
        var high = lineOffsets.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let value = lineOffsets[middle]
            if value == offset { return middle }
            if value < offset { low = middle + 1 } else { high = middle - 1 }
        }
        return nil
    }

    func read(at offset: UInt64, count: Int) throws(TranscriptFileError) -> [UInt8] {
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let result = buffer.withUnsafeMutableBytes { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return pread(descriptor, base + filled, count - filled, off_t(offset) + off_t(filled))
            }
            if result < 0 {
                if errno == EINTR { continue }
                throw .system(errno: errno)
            }
            if result == 0 { break }
            filled += result
        }
        if filled < count {
            buffer.removeSubrange(filled...)
        }
        return buffer
    }

    private func consumeAppended(
        keepingLines: Bool,
        _ body: (UInt64, UnsafeRawBufferPointer) -> Void
    ) throws(TranscriptFileError) {
        var position = indexedEnd + UInt64(pending.count)
        var lineStart = indexedEnd
        var carried = pending
        var chunk = [UInt8](repeating: 0, count: Self.chunkSize)
        while true {
            let count = chunk.withUnsafeMutableBytes { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return pread(descriptor, base, Self.chunkSize, off_t(position))
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw .system(errno: errno)
            }
            if count == 0 { break }
            chunk.withUnsafeBytes { buffer in
                var segmentStart = 0
                while segmentStart <= count,
                      let newline = Self.firstNewline(in: buffer, from: segmentStart, to: count) {
                    let segment = UnsafeRawBufferPointer(rebasing: buffer[segmentStart..<newline])
                    lineOffsets.append(lineStart)
                    if keepingLines {
                        if carried.isEmpty {
                            body(lineStart, segment)
                        } else {
                            carried.append(contentsOf: segment)
                            carried.withUnsafeBytes { body(lineStart, $0) }
                        }
                    }
                    carried.removeAll(keepingCapacity: true)
                    lineStart = position + UInt64(newline) + 1
                    segmentStart = newline + 1
                }
                if segmentStart < count {
                    carried.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[segmentStart..<count]))
                }
            }
            position += UInt64(count)
        }
        indexedEnd = lineStart
        pending = carried
    }

    private static func firstNewline(in buffer: UnsafeRawBufferPointer, from start: Int, to end: Int) -> Int? {
        guard start < end, let base = buffer.baseAddress else { return nil }
        guard let found = memchr(base + start, 0x0A, end - start) else { return nil }
        return base.distance(to: UnsafeRawPointer(found))
    }
}
