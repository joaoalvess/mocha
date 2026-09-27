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
        if let subagent = session.subagent {
            return TranscriptFileStatus.of(path: subagent.path) != nil ? subagent.path : nil
        }
        if let transcriptPath = trustedTranscriptPath(of: session) {
            return transcriptPath
        }
        return existingPath(forSessionId: session.sessionId)
    }

    func trustedTranscriptPath(of session: TranscriptSession) -> String? {
        guard let requested = session.transcriptPath else { return nil }
        let fileName = "\(session.sessionId).jsonl"
        guard let standardized = Self.standardized(requested),
              standardized.last == fileName,
              let resolved = Self.resolved(standardized),
              resolved.last == fileName,
              let root = Self.standardized(projectsRoot).flatMap(Self.resolved),
              resolved.count > root.count,
              resolved.starts(with: root)
        else {
            transcriptLogger.debug("ignoring the transcript_path of session \(session.sessionId, privacy: .public): not <session>.jsonl inside the projects root")
            return nil
        }
        return Self.path(from: standardized)
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
        if let subagent = session.subagent {
            return [Self.nearestExistingDirectory(from: (subagent.path as NSString).deletingLastPathComponent)]
        }
        if let transcriptPath = trustedTranscriptPath(of: session) {
            return [Self.nearestExistingDirectory(from: (transcriptPath as NSString).deletingLastPathComponent)]
        }
        guard Self.directoryExists(projectsRoot) else {
            return [Self.nearestExistingDirectory(from: projectsRoot)]
        }
        return [projectsRoot] + projectDirectories()
    }

    private static func standardized(_ path: String) -> [String]? {
        guard path.hasPrefix("/") else { return nil }
        var components: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                _ = components.popLast()
            default:
                components.append(String(component))
            }
        }
        return components
    }

    private static func resolved(_ components: [String]) -> [String]? {
        var existing = components
        var missing: [String] = []
        while true {
            let candidate = path(from: existing)
            var info = stat()
            if lstat(candidate, &info) == 0 { break }
            guard errno == ENOENT, let last = existing.popLast() else { return nil }
            missing.insert(last, at: 0)
        }
        guard let real = realPath(path(from: existing)), let resolved = standardized(real) else { return nil }
        return resolved + missing
    }

    private static func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private static func path(from components: [String]) -> String {
        "/" + components.joined(separator: "/")
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
