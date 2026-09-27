import Darwin
import Foundation
import MochaProtocol

struct ScannedHeader: Sendable, Equatable {
    var header: TranscriptHeader
    var activity: ScannedActivity?
}

public enum TranscriptHeaderScanner {
    public static let scanLimit: UInt64 = 8 << 20

    private static let chunkSize = 1 << 18
    private static let titleMarker = Array("ai-title".utf8)
    private static let permissionMarker = Array("permission-mode".utf8)
    private static let assistantMarker = Array("assistant".utf8)
    private static let userMarker = Array("user".utf8)
    private static let queuedCommandMarker = Array("queued_command".utf8)
    private static let turnDurationMarker = Array("turn_duration".utf8)
    private static let toolUseMarker = Array("tool_use".utf8)
    private static let versionMarker = Array("\"version\"".utf8)
    private static let timestampMarker = Array("\"timestamp\"".utf8)

    public static func header(ofFileAt path: String, mode: TranscriptParseMode = .main) throws(TranscriptFileError) -> TranscriptHeader {
        try scan(fileAt: path, mode: mode).header
    }

    static func scan(fileAt path: String, limit: UInt64 = scanLimit, mode: TranscriptParseMode = .main) throws(TranscriptFileError) -> ScannedHeader {
        let file = try TranscriptFile(path: path)
        guard let size = file.status()?.size else { return ScannedHeader(header: TranscriptHeader()) }
        guard let end = try lastLineEnd(in: file, size: size) else { return ScannedHeader(header: TranscriptHeader()) }
        return try scan(file, end: end, limit: limit, mode: mode)
    }

    static func scan(
        _ file: TranscriptFile,
        end: UInt64,
        limit: UInt64 = scanLimit,
        mode: TranscriptParseMode = .main
    ) throws(TranscriptFileError) -> ScannedHeader {
        var state = BackwardMetaState(lineMode: mode.scanLineMode)
        try forEachLineBackward(in: file, end: end, limit: limit) { offset, bytes in
            state.consider(bytes, offset: offset)
            return !state.isComplete
        }
        var scanned = state.result
        scanned.header.sessionStartedAt = try firstTimestamp(in: file, end: min(end, limit))
        return scanned
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

    private static func firstTimestamp(in file: TranscriptFile, end: UInt64) throws(TranscriptFileError) -> Date? {
        var found: Date?
        try forEachLineForward(in: file, end: end) { bytes in
            guard contains(timestampMarker, in: bytes), let date = LineOutline.of(bytes)?.date else { return true }
            found = date
            return false
        }
        return found
    }

    private static func forEachLineForward(
        in file: TranscriptFile,
        end: UInt64,
        _ body: (UnsafeRawBufferPointer) -> Bool
    ) throws(TranscriptFileError) {
        var position: UInt64 = 0
        var carried: [UInt8] = []
        while position < end {
            let count = Int(min(UInt64(chunkSize), end - position))
            var buffer = carried
            buffer.append(contentsOf: try file.read(at: position, count: count))
            var keepGoing = true
            buffer.withUnsafeBytes { bytes in
                var lineStart = 0
                while lineStart < bytes.count, let newline = nextNewline(in: bytes, from: lineStart) {
                    if !body(UnsafeRawBufferPointer(rebasing: bytes[lineStart..<newline])) {
                        keepGoing = false
                        return
                    }
                    lineStart = newline + 1
                }
                carried = Array(bytes[lineStart...])
            }
            guard keepGoing else { return }
            position += UInt64(count)
        }
    }

    private static func forEachLineBackward(
        in file: TranscriptFile,
        end: UInt64,
        limit: UInt64,
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
            guard keepGoing, start == 0 || end - start < limit else { return }
            position = start
        }
        if !carried.isEmpty {
            carried.withUnsafeBytes { _ = body(0, $0) }
        }
    }

    private static func nextNewline(in bytes: UnsafeRawBufferPointer, from start: Int) -> Int? {
        guard start < bytes.count, let base = bytes.baseAddress else { return nil }
        guard let found = memchr(base + start, 0x0A, bytes.count - start) else { return nil }
        return base.distance(to: UnsafeRawPointer(found))
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

    fileprivate struct BackwardMetaState {
        let lineMode: LineMode
        private(set) var header = TranscriptHeader()
        private var hasTitle = false
        private var hasPermission = false
        private var hasModel = false
        private var hasContext = false
        private var hasVersion = false
        private var hasPreview = false
        private var hasTurnStart = false
        private var hasTurnEnd = false
        private var lastToolCall: ScannedActivity?
        private var runningToolCall: ScannedActivity?
        private var laterResults: [String: Bool] = [:]

        var isComplete: Bool {
            hasTitle && hasPermission && hasModel && hasContext && hasVersion
                && hasPreview && hasTurnStart && hasTurnEnd && runningToolCall != nil
        }

        var result: ScannedHeader {
            let activity = runningToolCall ?? lastToolCall
            var header = header
            header.activity = activity.map { ToolActivity(call: $0.call) }
            return ScannedHeader(header: header, activity: activity)
        }

        private var searchesToolCalls: Bool {
            runningToolCall == nil
        }

        mutating func consider(_ bytes: UnsafeRawBufferPointer, offset: UInt64) {
            typealias Scanner = TranscriptHeaderScanner
            let wanted = needsFullParse(bytes)
            guard wanted || searchesToolCalls else { return }
            if Scanner.contains(Scanner.toolUseMarker, in: bytes), let outline = LineOutline.of(bytes) {
                if let results = outline.toolResults {
                    absorbVersion(outline.version)
                    guard searchesToolCalls else { return }
                    for result in results.reversed() {
                        laterResults[result.toolUseId] = result.isError
                    }
                    return
                }
                if let ids = outline.toolUseIds {
                    if wanted || needsToolCall(from: ids) {
                        absorb(TranscriptLineParser.parse(bytes, offset: offset, mode: lineMode))
                    } else {
                        for id in ids.reversed() {
                            laterResults.removeValue(forKey: id)
                        }
                    }
                    return
                }
            }
            guard wanted else { return }
            absorb(TranscriptLineParser.parse(bytes, offset: offset, mode: lineMode))
        }

        private func needsToolCall(from ids: [String]) -> Bool {
            guard searchesToolCalls, !ids.isEmpty else { return false }
            return lastToolCall == nil || ids.contains { laterResults[$0] == nil }
        }

        private func needsFullParse(_ bytes: UnsafeRawBufferPointer) -> Bool {
            typealias Scanner = TranscriptHeaderScanner
            func mentions(_ marker: [UInt8]) -> Bool {
                Scanner.contains(marker, in: bytes)
            }
            return (!hasTitle && mentions(Scanner.titleMarker))
                || (!hasPermission && mentions(Scanner.permissionMarker))
                || ((!hasModel || !hasContext) && mentions(Scanner.assistantMarker))
                || (!hasVersion && mentions(Scanner.versionMarker))
                || (!hasTurnEnd && mentions(Scanner.turnDurationMarker))
                || ((!hasPreview || !hasTurnStart) && mentions(Scanner.userMarker))
                || (!hasPreview && (mentions(Scanner.assistantMarker) || mentions(Scanner.queuedCommandMarker)))
        }

        private mutating func absorbVersion(_ version: String?) {
            guard !hasVersion, let version else { return }
            header.claudeVersion = version
            hasVersion = true
        }

        private mutating func absorb(_ line: ParsedLine) {
            absorbVersion(line.version)
            for effect in line.effects.reversed() {
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
                case .contextTokens(let tokens) where !hasContext:
                    header.contextTokens = tokens
                    hasContext = true
                case .turnStarted where !hasTurnStart:
                    header.turnStartedAt = line.date
                    hasTurnStart = true
                case .turnEnded where !hasTurnEnd:
                    header.turnEndedAt = line.date
                    hasTurnEnd = true
                case .toolResult(let outcome) where searchesToolCalls:
                    laterResults[outcome.toolUseId] = outcome.isError
                case .item(let item):
                    absorb(item)
                default:
                    break
                }
            }
        }

        private mutating func absorb(_ item: ChatItem) {
            switch item.kind {
            case .userPrompt, .assistantText:
                guard !hasPreview else { return }
                header.preview = MessagePreview(transcriptItem: item)
                hasPreview = true
            case .toolCall(var call):
                guard searchesToolCalls else { return }
                if let isError = laterResults.removeValue(forKey: call.toolUseId) {
                    call.status = isError ? .failed : .succeeded
                }
                let scanned = ScannedActivity(itemId: item.id, call: call)
                if lastToolCall == nil {
                    lastToolCall = scanned
                }
                if call.status == .running {
                    runningToolCall = scanned
                }
            default:
                break
            }
        }
    }
}
