import Foundation
import MochaTranscript
import Synchronization

final class TranscriptLocator: Sendable {
    let projectsRoot: String
    private let cache = Mutex<[String: String]>([:])

    init(projectsRoot: String) {
        self.projectsRoot = projectsRoot
    }

    func path(for session: TranscriptSession) -> String? {
        if let transcriptPath = session.transcriptPath {
            return transcriptPath
        }
        return existingPath(forSessionId: session.sessionId)
    }

    func existingPath(forSessionId sessionId: String) -> String? {
        let fileName = "\(sessionId).jsonl"
        if let cached = cache.withLock({ $0[sessionId] }) {
            if TranscriptFileStatus.of(path: cached) != nil { return cached }
            cache.withLock { _ = $0.removeValue(forKey: sessionId) }
        }
        for directory in projectDirectories() {
            let candidate = (directory as NSString).appendingPathComponent(fileName)
            if TranscriptFileStatus.of(path: candidate) != nil {
                cache.withLock { $0[sessionId] = candidate }
                return candidate
            }
        }
        return nil
    }

    func projectDirectories() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: projectsRoot) else { return [] }
        return entries.sorted().compactMap { entry in
            let path = (projectsRoot as NSString).appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return path
        }
    }

    func directoriesToWatch(for session: TranscriptSession) -> [String] {
        if let transcriptPath = session.transcriptPath {
            return [Self.nearestExistingDirectory(from: (transcriptPath as NSString).deletingLastPathComponent)]
        }
        guard Self.directoryExists(projectsRoot) else {
            return [Self.nearestExistingDirectory(from: projectsRoot)]
        }
        return [projectsRoot] + projectDirectories()
    }

    private static func nearestExistingDirectory(from path: String) -> String {
        var current = path
        while !directoryExists(current), current != "/", !current.isEmpty {
            current = (current as NSString).deletingLastPathComponent
        }
        return current.isEmpty ? "/" : current
    }

    private static func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
