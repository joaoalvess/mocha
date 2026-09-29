import Foundation

struct AgentControls: Sendable, Equatable {
    struct Override: Sendable, Equatable {
        var value: String
        var transcriptBaseline: String?

        func resolve(transcript: String?) -> String? {
            transcriptBaseline == transcript ? value : transcript
        }
    }

    var sessionId: String?
    var permissionMode: Override?
    var model: Override?
    var effort: String?
    var knowsEffort = false

    init(sessionId: String?) {
        self.sessionId = sessionId
    }

    func permissionMode(transcript: String?) -> String? {
        permissionMode?.resolve(transcript: transcript) ?? transcript
    }

    func model(transcript: String?) -> String? {
        model?.resolve(transcript: transcript) ?? transcript
    }

    func effort(fallback: String?) -> String? {
        knowsEffort ? effort : fallback
    }

    static func hasEffort(model: String?) -> Bool {
        !(model?.lowercased().contains("haiku") ?? false)
    }
}
