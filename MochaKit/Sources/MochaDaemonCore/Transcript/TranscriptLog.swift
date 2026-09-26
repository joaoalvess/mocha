import Foundation
import MochaTranscript
import os

let transcriptLogger = Logger(subsystem: "com.joaoalves.mocha", category: "transcript")

extension TranscriptMeta {
    init(header: TranscriptHeader, lastModified: Date?) {
        self.init(
            title: header.title,
            model: header.model,
            branch: header.branch,
            permissionMode: header.permissionMode,
            claudeVersion: header.claudeVersion,
            lastModified: lastModified
        )
    }

    func hasSameContent(as other: TranscriptMeta) -> Bool {
        title == other.title
            && model == other.model
            && branch == other.branch
            && permissionMode == other.permissionMode
            && claudeVersion == other.claudeVersion
    }
}
