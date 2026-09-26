import Darwin
import Foundation

public enum TranscriptHeaderScanner {
    private static let chunkSize = 1 << 18
    private static let titleMarker = Array("ai-title".utf8)
    private static let permissionMarker = Array("permission-mode".utf8)
    private static let assistantMarker = Array("assistant".utf8)
    private static let versionMarker = Array("\"version\"".utf8)

    public static func header(ofFileAt path: String) throws(TranscriptFileError) -> TranscriptHeader {
        let file = try TranscriptFile(path: path)
        guard let size = file.status()?.size else { return TranscriptHeader() }
        guard let end = try lastLineEnd(in: file, size: size) else { return TranscriptHeader() }
        return try scan(file, end: end)
    }

    static func scan(_ file: TranscriptFile, end: UInt64) throws(TranscriptFileError) -> TranscriptHeader {
        var scanner = BackwardHeaderState()
        try forEachLineBackward(in: file, end: end) { offset, bytes in
            scanner.consider(bytes, offset: offset)
            return !scanner.isComplete
        }
        return scanner.header
    }

    private static func lastLineEnd(in file: TranscriptFile, size: UInt64) throws(TranscriptFileError) -> UInt64? {
        var position = size
        while position > 0 {
            let count = Int(min(UInt64(chunkSize), position))
            let chunk = try file.read(at: position - UInt64(count), count: count)
            if let newline = chunk.lastIndex(of: 0x0A) {
                return position - UInt64(count) + UInt64(newline) + 1
            }
            position -= UInt64(count)
        }
        return nil
    }

    private static func forEachLineBackward(
        in file: TranscriptFile,
        end: UInt64,
        _ body: (UInt64, UnsafeRawBufferPointer) -> Bool
    ) throws(TranscriptFileError) {
        var position = end
        var carried: [UInt8] = []
        while position > 0 {
            let count = Int(min(UInt64(chunkSize), position))
            let start = position - UInt64(count)
            var buffer = try file.read(at: start, count: count)
            buffer.append(contentsOf: carried)
            var lineEnd = buffer.count
            if start + UInt64(buffer.count) == end, buffer.last == 0x0A {
                lineEnd -= 1
            }
            var keepGoing = true
            buffer.withUnsafeBytes { bytes in
                var cursor = lineEnd
                while cursor > 0 {
                    guard let newline = lastNewline(in: bytes, before: cursor) else { break }
                    let line = UnsafeRawBufferPointer(rebasing: bytes[(newline + 1)..<cursor])
                    if !body(start + UInt64(newline) + 1, line) {
                        keepGoing = false
                        return
                    }
                    cursor = newline
                }
                carried = Array(bytes[0..<cursor])
            }
            guard keepGoing else { return }
            position = start
        }
        if !carried.isEmpty {
            carried.withUnsafeBytes { _ = body(0, $0) }
        }
    }

    private static func lastNewline(in bytes: UnsafeRawBufferPointer, before end: Int) -> Int? {
        var index = end - 1
        while index >= 0 {
            if bytes[index] == 0x0A { return index }
            index -= 1
        }
        return nil
    }

    fileprivate static func contains(_ marker: [UInt8], in bytes: UnsafeRawBufferPointer) -> Bool {
        guard let base = bytes.baseAddress, bytes.count >= marker.count else { return false }
        return marker.withUnsafeBytes { needle in
            guard let needleBase = needle.baseAddress else { return false }
            return memmem(base, bytes.count, needleBase, needle.count) != nil
        }
    }

    fileprivate struct BackwardHeaderState {
        var header = TranscriptHeader()
        private var hasTitle = false
        private var hasPermission = false
        private var hasModel = false
        private var hasVersion = false

        var isComplete: Bool {
            hasTitle && hasPermission && hasModel && hasVersion
        }

        mutating func consider(_ bytes: UnsafeRawBufferPointer, offset: UInt64) {
            typealias Scanner = TranscriptHeaderScanner
            let relevant = (!hasTitle && Scanner.contains(Scanner.titleMarker, in: bytes))
                || (!hasPermission && Scanner.contains(Scanner.permissionMarker, in: bytes))
                || (!hasModel && Scanner.contains(Scanner.assistantMarker, in: bytes))
                || (!hasVersion && Scanner.contains(Scanner.versionMarker, in: bytes))
            guard relevant else { return }
            let line = TranscriptLineParser.parse(bytes, offset: offset)
            if !hasVersion, let version = line.version {
                header.claudeVersion = version
                hasVersion = true
            }
            for effect in line.effects {
                switch effect {
                case .title(let title) where !hasTitle:
                    header.title = title
                    hasTitle = true
                case .permissionMode(let mode) where !hasPermission:
                    header.permissionMode = mode
                    hasPermission = true
                case .modelAndBranch(let model, let branch) where !hasModel:
                    header.model = model
                    header.branch = branch
                    hasModel = true
                default:
                    break
                }
            }
        }
    }
}
