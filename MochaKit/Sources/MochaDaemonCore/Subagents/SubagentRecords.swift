import Foundation
import MochaProtocol
import MochaTranscript
import os

let subagentLogger = Logger(subsystem: "com.joaoalves.mocha", category: "subagents")

struct SubagentMeta: Sendable, Equatable {
    static let workflowAgentType = "workflow-subagent"

    var agentType: String?
    var description: String?
    var toolUseId: String?
    var parentAgentId: String?
    var isFork = false
    var workflowPhase: String?
    var name: String?
    var stoppedByUser = false

    init(agentType: String? = nil, description: String? = nil, toolUseId: String? = nil, parentAgentId: String? = nil) {
        self.agentType = agentType
        self.description = description
        self.toolUseId = toolUseId
        self.parentAgentId = parentAgentId
    }

    static func read(path: String) -> SubagentMeta? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        var meta = SubagentMeta(
            agentType: object["agentType"] as? String,
            description: object["description"] as? String,
            toolUseId: object["toolUseId"] as? String,
            parentAgentId: object["parentAgentId"] as? String
        )
        meta.isFork = object["isFork"] as? Bool ?? false
        meta.workflowPhase = object["workflowPhase"] as? String
        meta.name = object["name"] as? String
        meta.stoppedByUser = object["stoppedByUser"] as? Bool ?? false
        return meta
    }

    var isSkill: Bool {
        name != nil && toolUseId == nil
    }

    var forkToolUseId: String? {
        isFork ? toolUseId : nil
    }
}

struct SubagentNotificationRecord: Sendable, Equatable {
    var notification: TaskNotification
    var at: Date?
}

struct SubagentFileRecord: Sendable {
    let agentId: String
    var path: String
    var metaPath: String
    var runId: String?
    var meta: SubagentMeta?
    var scanner = SubagentFileScanner(forkToolUseId: nil)
    var reader = AppendedLineReader()
    var hasRead = false

    init(agentId: String, path: String, metaPath: String, runId: String?) {
        self.agentId = agentId
        self.path = path
        self.metaPath = metaPath
        self.runId = runId
    }
}

struct WorkflowJournalEntry: Sendable, Equatable {
    var agentId: String
    var label: String
    var phase: String?
}

struct WorkflowFinal: Sendable, Equatable {
    var status: WorkflowStatus?
    var taskId: String?
    var workflowName: String?
    var scriptPath: String?
    var phases: [WorkflowScriptPhase]
    var agentCount: Int?
    var toolUses: Int?
    var durationMs: Int?
    var progress: [String: SubagentStatus]

    static func read(path: String) -> WorkflowFinal? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let phases = (object["phases"] as? [[String: Any]] ?? []).compactMap { phase -> WorkflowScriptPhase? in
            guard let title = phase["title"] as? String else { return nil }
            return WorkflowScriptPhase(title: title, detail: phase["detail"] as? String)
        }
        var progress: [String: SubagentStatus] = [:]
        for entry in object["workflowProgress"] as? [[String: Any]] ?? [] where entry["type"] as? String == "workflow_agent" {
            guard let agentId = entry["agentId"] as? String else { continue }
            switch entry["state"] as? String {
            case "done": progress[agentId] = .completed
            case "error": progress[agentId] = .failed
            default: break
            }
        }
        let status: WorkflowStatus? = switch object["status"] as? String {
        case "completed": .completed
        case "failed": .failed
        case "killed": .stopped
        default: nil
        }
        return WorkflowFinal(
            status: status,
            taskId: object["taskId"] as? String,
            workflowName: object["workflowName"] as? String,
            scriptPath: object["scriptPath"] as? String,
            phases: phases,
            agentCount: object["agentCount"] as? Int,
            toolUses: object["totalToolCalls"] as? Int,
            durationMs: object["durationMs"] as? Int,
            progress: progress
        )
    }
}

struct WorkflowRecord: Sendable {
    let runId: String
    var directory: String
    var journal = AppendedLineReader()
    var keys: [String] = []
    var latest: [String: WorkflowJournalEntry] = [:]
    var results: Set<String> = []
    var journalPhases: [String] = []
    var final: WorkflowFinal?
    var scriptMeta: WorkflowScriptMeta?
    var scriptSource: String?

    init(runId: String, directory: String) {
        self.runId = runId
        self.directory = directory
    }

    var journalPath: String {
        (directory as NSString).appendingPathComponent("journal.jsonl")
    }

    var latestAgentIds: Set<String> {
        Set(latest.values.map(\.agentId))
    }

    mutating func absorbJournal(_ line: [UInt8]) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }
        switch type {
        case "started":
            guard let key = object["key"] as? String, let agentId = object["agentId"] as? String else { return }
            if latest[key] == nil {
                keys.append(key)
            }
            let phase = object["phase"] as? String
            latest[key] = WorkflowJournalEntry(agentId: agentId, label: object["label"] as? String ?? "", phase: phase)
            if let phase, !journalPhases.contains(phase) {
                journalPhases.append(phase)
            }
        case "result":
            if let agentId = object["agentId"] as? String {
                results.insert(agentId)
            }
        default:
            break
        }
    }
}

struct WorkflowLaunchRecord: Sendable, Equatable {
    var toolUseId: String
    var script: String?
    var scriptPath: String?
    var at: Date?
    var runId: String?
    var taskId: String?
    var workflowName: String?
    var resultScriptPath: String?
}

enum SubagentFileName {
    static func agentId(fromTranscript name: String) -> String? {
        guard name.hasPrefix("agent-"), name.hasSuffix(".jsonl"), !name.contains(".meta") else { return nil }
        let id = String(name.dropFirst("agent-".count).dropLast(".jsonl".count))
        return isValidId(id) ? id : nil
    }

    static func agentId(fromMeta name: String) -> String? {
        guard name.hasPrefix("agent-"), name.hasSuffix(".meta.json") else { return nil }
        let id = String(name.dropFirst("agent-".count).dropLast(".meta.json".count))
        return isValidId(id) ? id : nil
    }

    static func isValidId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.utf8.allSatisfy { byte in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
        }
    }
}
