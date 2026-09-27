import Foundation

enum DictationFailure: Error, Equatable, Sendable {
    case microphoneDenied
    case modelDownloadFailed
    case audioUnavailable
    case recognitionFailed

    var message: String {
        switch self {
        case .microphoneDenied: "Sem acesso ao microfone. Libere em Ajustes › Mocha."
        case .modelDownloadFailed: "Não foi possível baixar o modelo de voz."
        case .audioUnavailable: "Não foi possível usar o microfone."
        case .recognitionFailed: "Não foi possível transcrever o ditado."
        }
    }
}

enum DictationPhase: Equatable, Sendable {
    case checking
    case unavailable
    case ready
    case preparing
    case downloading(fraction: Double)
    case listening
    case finishing
    case failed(DictationFailure)
}

enum DictationEvent: Equatable, Sendable {
    case availabilityResolved(isSupported: Bool)
    case startRequested
    case downloadProgressed(fraction: Double)
    case downloadFinished
    case listeningStarted
    case stopRequested
    case finished
    case failed(DictationFailure)
    case cancelled
}

enum DictationToggle: Equatable, Sendable {
    case start
    case stop
    case ignore
}

extension DictationPhase {
    var showsMicrophone: Bool {
        switch self {
        case .checking, .unavailable: false
        default: true
        }
    }

    var isListening: Bool {
        self == .listening
    }

    var isSessionActive: Bool {
        switch self {
        case .preparing, .downloading, .listening, .finishing, .failed: true
        case .checking, .unavailable, .ready: false
        }
    }

    var toggle: DictationToggle {
        switch self {
        case .ready, .failed: .start
        case .listening: .stop
        case .checking, .unavailable, .preparing, .downloading, .finishing: .ignore
        }
    }

    func applying(_ event: DictationEvent) -> DictationPhase {
        switch (self, event) {
        case (_, .availabilityResolved(isSupported: false)):
            .unavailable
        case (.checking, .availabilityResolved(isSupported: true)):
            .ready
        case (.ready, .startRequested), (.failed, .startRequested):
            .preparing
        case (.preparing, .downloadProgressed(let fraction)), (.downloading, .downloadProgressed(let fraction)):
            .downloading(fraction: Self.clamped(fraction))
        case (.downloading, .downloadFinished):
            .preparing
        case (.preparing, .listeningStarted), (.downloading, .listeningStarted):
            .listening
        case (.listening, .stopRequested):
            .finishing
        case (.listening, .finished), (.finishing, .finished):
            .ready
        case (.preparing, .failed(let failure)), (.downloading, .failed(let failure)),
             (.listening, .failed(let failure)), (.finishing, .failed(let failure)):
            .failed(failure)
        case (.preparing, .cancelled), (.downloading, .cancelled), (.listening, .cancelled),
             (.finishing, .cancelled), (.failed, .cancelled):
            .ready
        default:
            self
        }
    }

    private static func clamped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }
}

enum DictationText {
    static func appending(_ transcript: String, to draft: String) -> String {
        let text = trimmed(transcript)
        guard !text.isEmpty else { return draft }
        guard let last = draft.last, !last.isWhitespace else { return draft + text }
        return draft + " " + text
    }

    static func partial(_ transcript: String) -> String {
        trimmed(transcript)
    }

    static func visibleTail(of text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        let start = text.index(text.endIndex, offsetBy: -limit)
        let tail = text[start...]
        let startsAtWord = text[text.index(before: start)].isWhitespace
        let wholeWords = (startsAtWord ? tail : tail.drop { !$0.isWhitespace }).drop { $0.isWhitespace }
        return "…" + (wholeWords.isEmpty ? tail : wholeWords)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DictationLine: Equatable, Sendable {
    static let preparingText = "Preparando ditado…"
    static let listeningText = "Ouvindo…"
    static let transcriptCharacterLimit = 110

    let text: String
    let isTranscript: Bool

    init?(phase: DictationPhase, partial: String) {
        switch phase {
        case .preparing:
            text = Self.preparingText
            isTranscript = false
        case .listening where partial.isEmpty:
            text = Self.listeningText
            isTranscript = false
        case .listening, .finishing:
            guard !partial.isEmpty else { return nil }
            text = DictationText.visibleTail(of: partial, limit: Self.transcriptCharacterLimit)
            isTranscript = true
        case .downloading(let fraction):
            text = "Baixando modelo de voz… \(Int((fraction * 100).rounded()))%"
            isTranscript = false
        case .failed(let failure):
            text = failure.message
            isTranscript = false
        case .checking, .unavailable, .ready:
            return nil
        }
    }
}
