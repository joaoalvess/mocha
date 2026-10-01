import Foundation

public enum TranscriptParseMode: Sendable, Hashable {
    case main
    case subagent(forkToolUseId: String?)

    var initialLineMode: LineMode {
        switch self {
        case .main: .main
        case .subagent(let forkToolUseId?): .forkPrelude(toolUseId: forkToolUseId)
        case .subagent(nil): .subagent
        }
    }

    var scanLineMode: LineMode {
        switch self {
        case .main: .main
        case .subagent: .subagent
        }
    }
}

enum LineMode: Sendable, Hashable {
    case main
    case subagent
    case forkPrelude(toolUseId: String)
}

struct SequentialLineParser {
    private(set) var mode: LineMode
    var imageStore: TranscriptImageStore?

    init(_ parseMode: TranscriptParseMode, imageStore: TranscriptImageStore? = nil) {
        mode = parseMode.initialLineMode
        self.imageStore = imageStore
    }

    init(resuming mode: LineMode, imageStore: TranscriptImageStore? = nil) {
        self.mode = mode
        self.imageStore = imageStore
    }

    mutating func parse(_ bytes: UnsafeRawBufferPointer, offset: UInt64) -> ParsedLine {
        let parsed = TranscriptLineParser.parse(bytes, offset: offset, mode: mode, imageStore: imageStore)
        if parsed.crossesForkBoundary {
            mode = .subagent
        }
        return parsed
    }

    mutating func parse(_ bytes: [UInt8], offset: UInt64) -> ParsedLine {
        bytes.withUnsafeBytes { parse($0, offset: offset) }
    }
}

struct ForkBoundaryLocator {
    let parseMode: TranscriptParseMode
    private var boundaryLine: Int?
    private var scannedLines = 0

    init(_ parseMode: TranscriptParseMode) {
        self.parseMode = parseMode
    }

    mutating func mode(forLine index: Int, in file: TranscriptFile) throws(TranscriptFileError) -> LineMode {
        guard case .forkPrelude = parseMode.initialLineMode else { return parseMode.initialLineMode }
        if boundaryLine == nil {
            try advance(to: index, in: file)
        }
        guard let boundaryLine, index > boundaryLine else { return parseMode.initialLineMode }
        return .subagent
    }

    private mutating func advance(to index: Int, in file: TranscriptFile) throws(TranscriptFileError) {
        let end = min(index, file.lineCount)
        while scannedLines < end {
            let line = scannedLines
            scannedLines += 1
            let parsed = TranscriptLineParser.parse(try file.lineBytes(at: line), offset: file.lineOffsets[line], mode: parseMode.initialLineMode)
            if parsed.crossesForkBoundary {
                boundaryLine = line
                return
            }
        }
    }
}
