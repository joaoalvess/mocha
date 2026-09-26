import Foundation

struct TranscriptCursor: Sendable, Equatable {
    let sessionId: String
    let offset: UInt64

    init(sessionId: String, offset: UInt64) {
        self.sessionId = sessionId
        self.offset = offset
    }

    init?(_ text: String) {
        guard let separator = text.lastIndex(of: ":") else { return nil }
        let sessionId = String(text[..<separator])
        guard !sessionId.isEmpty, let offset = UInt64(text[text.index(after: separator)...]) else { return nil }
        self.sessionId = sessionId
        self.offset = offset
    }

    var text: String {
        "\(sessionId):\(offset)"
    }
}
