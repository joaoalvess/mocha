import Foundation
import MochaTranscript
import os

let transcriptLogger = Logger(subsystem: "com.joaoalves.mocha", category: "transcript")

extension TranscriptSession {
    var cursorKey: String {
        subagent.map { "\(sessionId)/\($0.agentId)" } ?? sessionId
    }

    var parseMode: TranscriptParseMode {
        subagent.map { .subagent(forkToolUseId: $0.forkToolUseId) } ?? .main
    }
}

extension TranscriptMeta {
    init(header: TranscriptHeader, lastModified: Date?) {
        self.init(
            title: header.title,
            model: header.model,
            branch: header.branch,
            permissionMode: header.permissionMode,
            claudeVersion: header.claudeVersion,
            lastModified: lastModified,
            preview: header.preview,
            activity: header.activity,
            contextTokens: header.contextTokens,
            sessionStartedAt: header.sessionStartedAt,
            turnStartedAt: header.turnStartedAt,
            turnEndedAt: header.turnEndedAt
        )
    }

    func hasSameContent(as other: TranscriptMeta) -> Bool {
        var mine = self
        var theirs = other
        mine.lastModified = nil
        theirs.lastModified = nil
        return mine == theirs
    }
}
