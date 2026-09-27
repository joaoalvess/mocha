import Dispatch
import Foundation
import MochaProtocol
import MochaTranscript

struct SubagentStoreHooks: Sendable {
    var mainBytesRead: (@Sendable (String, Int) -> Void)?

    init(mainBytesRead: (@Sendable (String, Int) -> Void)? = nil) {
        self.mainBytesRead = mainBytesRead
    }
}

public actor SubagentStore: SubagentProviding {
    public static let mainScanLimit: UInt64 = 8 << 20
    static let scriptLimit = 1 << 20

    private struct SessionRecord {
        let sessionId: String
        var mainPath: String?
        var main: AppendedLineReader?
        var agents: [String: SubagentFileRecord] = [:]
        var workflows: [String: WorkflowRecord] = [:]
        var notifications: [String: SubagentNotificationRecord] = [:]
        var workflowNotifications: [String: SubagentNotificationRecord] = [:]
        var launches: [String: WorkflowLaunchRecord] = [:]
        var watches: [String: FileSystemWatch] = [:]

        var directory: String? {
            mainPath.map { ($0 as NSString).deletingPathExtension }
        }
    }

    private static var directoryEvents: DispatchSource.FileSystemEvent { [.write, .delete, .rename] }
    private static var fileEvents: DispatchSource.FileSystemEvent { [.write, .extend, .delete, .rename] }

    private let locator: TranscriptLocator
    private let hooks: SubagentStoreHooks
    private var observed: Set<String> = []
    private var sessions: [String: SessionRecord] = [:]
    private let broadcast = SubagentEventBroadcast()
    private var emittedAgents: [String: SubagentState] = [:]
    private var emittedWorkflows: [String: WorkflowState] = [:]
    private var emittedCounts: [String: Int] = [:]
    private let changes: AsyncStream<String>.Continuation
    private let changeStream: AsyncStream<String>
    private var changeLoop: Task<Void, Never>?

    public init(projectsRoot: String = TranscriptStore.defaultProjectsRoot) {
        self.init(projectsRoot: projectsRoot, hooks: SubagentStoreHooks())
    }

    init(projectsRoot: String, hooks: SubagentStoreHooks) {
        locator = TranscriptLocator(projectsRoot: projectsRoot)
        self.hooks = hooks
        let (stream, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(256))
        changes = continuation
        changeStream = stream
    }

    deinit {
        changes.finish()
        changeLoop?.cancel()
    }

    public nonisolated func events() -> AsyncStream<SubagentEvent> {
        broadcast.subscribe()
    }

    public func observe(sessions requested: Set<String>) async {
        startChangeLoopIfNeeded()
        let removed = observed.subtracting(requested)
        let added = requested.subtracting(observed)
        observed = requested
        for sessionId in removed {
            sessions[sessionId]?.watches.removeAll()
        }
        for sessionId in added.sorted() {
            refresh(sessionId)
        }
    }

    public func runningCount(session sessionId: String) async -> Int {
        guard observed.contains(sessionId) else { return 0 }
        return runningCount(in: sessionId)
    }

    public func subagents(session sessionId: String) async -> [SubagentSummary] {
        if !observed.contains(sessionId) {
            refresh(sessionId, watching: false)
        }
        guard let record = sessions[sessionId] else { return [] }
        let states = record.agents.values
            .filter { $0.runId == nil && !($0.meta?.isSkill ?? false) }
            .map { state(of: $0, in: record) }
        return SubagentOrdering.listed(states)
    }

    public func state(_ agentId: String) async -> SubagentState? {
        for sessionId in observed.sorted() {
            guard let record = sessions[sessionId], let file = record.agents[agentId] else { continue }
            return state(of: file, in: record)
        }
        return nil
    }

    public func workflow(_ runId: String) async -> WorkflowState? {
        for sessionId in observed.sorted() {
            guard let record = sessions[sessionId], let workflow = record.workflows[runId] else { continue }
            return workflowState(of: workflow, in: record)
        }
        return nil
    }

    public func transcript(session sessionId: String, agentId: String) async -> SubagentTranscript? {
        guard SubagentFileName.isValidId(agentId) else { return nil }
        let fileName = "agent-\(agentId).jsonl"
        for project in locator.projectDirectories() {
            let subagents = ((project as NSString).appendingPathComponent(sessionId) as NSString).appendingPathComponent("subagents")
            var candidates = [(subagents as NSString).appendingPathComponent(fileName)]
            let workflows = (subagents as NSString).appendingPathComponent("workflows")
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: workflows))?.sorted() ?? [] where entry.hasPrefix("wf_") {
                candidates.append(((workflows as NSString).appendingPathComponent(entry) as NSString).appendingPathComponent(fileName))
            }
            for candidate in candidates where TranscriptFileStatus.of(path: candidate) != nil {
                let meta = SubagentMeta.read(path: Self.metaPath(forTranscript: candidate))
                return SubagentTranscript(agentId: agentId, path: Self.realPath(candidate) ?? candidate, forkToolUseId: meta?.forkToolUseId)
            }
        }
        return nil
    }

    private func startChangeLoopIfNeeded() {
        guard changeLoop == nil else { return }
        let stream = changeStream
        changeLoop = Task { [weak self] in
            for await sessionId in stream {
                await self?.fileSystemChanged(sessionId)
            }
        }
    }

    private func fileSystemChanged(_ sessionId: String) {
        guard observed.contains(sessionId) else { return }
        refresh(sessionId)
    }

    private func refresh(_ sessionId: String, watching: Bool = true) {
        var record = sessions[sessionId] ?? SessionRecord(sessionId: sessionId)
        if record.mainPath == nil || record.mainPath.map({ TranscriptFileStatus.of(path: $0) == nil }) == true {
            record.mainPath = locator.existingPath(forSessionId: sessionId)
        }
        readMain(&record)
        if let directory = record.directory {
            discover(&record, directory: directory)
        }
        for agentId in Array(record.agents.keys) {
            guard var file = record.agents[agentId] else { continue }
            read(&file)
            record.agents[agentId] = file
        }
        for runId in Array(record.workflows.keys) {
            guard var workflow = record.workflows[runId] else { continue }
            readWorkflow(&workflow, in: record)
            record.workflows[runId] = workflow
        }
        if watching {
            updateWatches(&record)
        }
        sessions[sessionId] = record
        if observed.contains(sessionId) {
            emitChanges(in: sessionId)
        }
    }

    private func readMain(_ record: inout SessionRecord) {
        guard let path = record.mainPath else { return }
        var reader = record.main ?? AppendedLineReader.tail(of: path, limit: Self.mainScanLimit)
        let sessionId = record.sessionId
        let batch = reader.read(path: path) { hooks.mainBytesRead?(sessionId, $0) }
        record.main = reader
        for line in batch.lines {
            for signal in SubagentSignalScanner.signals(in: line) {
                absorb(signal, into: &record)
            }
        }
    }

    private func absorb(_ signal: SubagentSignal, into record: inout SessionRecord) {
        switch signal {
        case .notification(let notification, let at, let enqueued):
            guard let taskId = notification.taskId else { return }
            switch notification.kind {
            case .agent:
                var incoming = SubagentNotificationRecord(notification: notification, at: at)
                if !enqueued,
                   let existing = record.notifications[taskId],
                   existing.notification.status == notification.status,
                   existing.notification.isInterim == notification.isInterim {
                    incoming.at = existing.at ?? at
                }
                record.notifications[taskId] = incoming
            case .workflow:
                record.workflowNotifications[taskId] = SubagentNotificationRecord(notification: notification, at: at)
            case .other:
                break
            }
        case .workflowLaunch(let toolUseId, let script, let scriptPath, let at):
            var launch = record.launches[toolUseId] ?? WorkflowLaunchRecord(toolUseId: toolUseId)
            launch.script = script
            launch.scriptPath = scriptPath
            launch.at = at
            record.launches[toolUseId] = launch
        case .workflowLaunched(let toolUseId, let runId, let taskId, let workflowName, let scriptPath):
            var launch = record.launches[toolUseId] ?? WorkflowLaunchRecord(toolUseId: toolUseId)
            launch.runId = runId
            launch.taskId = taskId
            launch.workflowName = workflowName
            launch.resultScriptPath = scriptPath
            record.launches[toolUseId] = launch
        }
    }

    private func discover(_ record: inout SessionRecord, directory: String) {
        let subagents = (directory as NSString).appendingPathComponent("subagents")
        for entry in Self.entries(of: subagents) {
            if let agentId = SubagentFileName.agentId(fromTranscript: entry) ?? SubagentFileName.agentId(fromMeta: entry),
               record.agents[agentId] == nil {
                let path = (subagents as NSString).appendingPathComponent("agent-\(agentId).jsonl")
                record.agents[agentId] = SubagentFileRecord(agentId: agentId, path: path, metaPath: Self.metaPath(forTranscript: path), runId: nil)
            }
        }
        let workflows = (subagents as NSString).appendingPathComponent("workflows")
        var seenDirectories = Set(record.workflows.values.map(\.directory))
        for entry in Self.entries(of: workflows) where entry.hasPrefix("wf_") {
            let link = (workflows as NSString).appendingPathComponent(entry)
            guard let real = Self.realPath(link), Self.isDirectory(real) else { continue }
            if record.workflows[entry] == nil, !seenDirectories.contains(real) {
                record.workflows[entry] = WorkflowRecord(runId: entry, directory: real)
                seenDirectories.insert(real)
            }
            guard let workflowDirectory = record.workflows[entry]?.directory else { continue }
            for file in Self.entries(of: workflowDirectory) {
                guard let agentId = SubagentFileName.agentId(fromTranscript: file) ?? SubagentFileName.agentId(fromMeta: file),
                      record.agents[agentId] == nil else {
                    continue
                }
                let path = (workflowDirectory as NSString).appendingPathComponent("agent-\(agentId).jsonl")
                record.agents[agentId] = SubagentFileRecord(agentId: agentId, path: path, metaPath: Self.metaPath(forTranscript: path), runId: entry)
            }
        }
    }

    private func read(_ file: inout SubagentFileRecord) {
        if let meta = SubagentMeta.read(path: file.metaPath), meta != file.meta {
            let forkChanged = meta.forkToolUseId != file.meta?.forkToolUseId
            file.meta = meta
            if forkChanged && file.hasRead {
                file.scanner = SubagentFileScanner(forkToolUseId: meta.forkToolUseId)
                file.reader = AppendedLineReader()
            }
        }
        if !file.hasRead {
            file.scanner = SubagentFileScanner(forkToolUseId: file.meta?.forkToolUseId)
            file.hasRead = true
        }
        let batch = file.reader.read(path: file.path) { _ in }
        if batch.restarted {
            file.scanner = SubagentFileScanner(forkToolUseId: file.meta?.forkToolUseId)
        }
        for line in batch.lines {
            file.scanner.consume(line)
        }
    }

    private func readWorkflow(_ workflow: inout WorkflowRecord, in record: SessionRecord) {
        let journalPath = workflow.journalPath
        let batch = workflow.journal.read(path: journalPath) { _ in }
        if batch.restarted {
            workflow.keys = []
            workflow.latest = [:]
            workflow.results = []
            workflow.journalPhases = []
        }
        for line in batch.lines {
            workflow.absorbJournal(line)
        }
        if workflow.final == nil {
            workflow.final = finalState(runId: workflow.runId, in: record)
        }
        if workflow.scriptMeta == nil, workflow.final?.phases.isEmpty ?? true {
            let launch = launch(forRun: workflow.runId, in: record)
            if let script = launch?.script {
                workflow.scriptMeta = WorkflowScriptMeta.parse(script)
            } else if let path = launch?.scriptPath ?? launch?.resultScriptPath ?? workflow.final?.scriptPath,
                      workflow.scriptSource != path {
                workflow.scriptSource = path
                workflow.scriptMeta = Self.readScript(path: path).flatMap(WorkflowScriptMeta.parse)
            }
        }
    }

    private func finalState(runId: String, in record: SessionRecord) -> WorkflowFinal? {
        guard let directory = record.directory else { return nil }
        let fileName = "\(runId).json"
        let own = ((directory as NSString).appendingPathComponent("workflows") as NSString).appendingPathComponent(fileName)
        if let final = WorkflowFinal.read(path: own) {
            return final
        }
        let project = (directory as NSString).deletingLastPathComponent
        for entry in Self.entries(of: project) where !entry.hasSuffix(".jsonl") {
            let candidate = (((project as NSString).appendingPathComponent(entry) as NSString).appendingPathComponent("workflows") as NSString)
                .appendingPathComponent(fileName)
            if candidate != own, let final = WorkflowFinal.read(path: candidate) {
                return final
            }
        }
        return nil
    }

    private func launch(forRun runId: String, in record: SessionRecord) -> WorkflowLaunchRecord? {
        record.launches.values.first { $0.runId == runId }
    }

    private func state(of file: SubagentFileRecord, in record: SessionRecord) -> SubagentState {
        let meta = file.meta
        let scanner = file.scanner
        let notification = record.notifications[file.agentId]
        var status: SubagentStatus
        var failureReason: String?
        switch scanner.ending {
        case .running: status = .running
        case .completed: status = .completed
        case .stopped: status = .stopped
        case .failed(let reason):
            status = .failed
            failureReason = reason
        }
        var durationMs: Int?
        if let notification, let notified = notification.notification.subagentStatus {
            let fileIsNewer = scanner.endingAt.map { ending in notification.at.map { ending > $0 } ?? false } ?? false
            if !fileIsNewer {
                status = notified
                if notified == .failed, failureReason == nil {
                    failureReason = notification.notification.failureReason
                }
                if !notification.notification.isInterim {
                    durationMs = notification.notification.durationMs
                }
            }
        }
        if let runId = file.runId, let workflow = record.workflows[runId] {
            if workflow.results.contains(file.agentId) {
                status = .completed
            }
            if let final = workflow.final?.progress[file.agentId] {
                status = final
            }
        }
        if status == .running, meta?.stoppedByUser == true {
            status = .stopped
        }
        if status != .failed {
            failureReason = nil
        }
        if status == .running {
            durationMs = nil
        } else if durationMs == nil, let startedAt = scanner.startedAt, let endingAt = scanner.endingAt {
            durationMs = max(0, Int((endingAt.timeIntervalSince(startedAt) * 1000).rounded()))
        }
        let isWorkflowAgent = file.runId != nil || meta?.agentType == SubagentMeta.workflowAgentType
        let journalLabel = file.runId.flatMap { record.workflows[$0] }?.latest.values.first { $0.agentId == file.agentId }?.label
        return SubagentState(
            agentId: file.agentId,
            sessionId: record.sessionId,
            toolUseId: meta?.toolUseId,
            parentAgentId: meta?.parentAgentId,
            runId: file.runId,
            agentType: SubagentType.displayName(for: meta?.agentType),
            description: (isWorkflowAgent ? journalLabel : nil) ?? meta?.description ?? "",
            status: status,
            activity: status == .running ? scanner.activity : nil,
            toolUses: scanner.toolUses,
            startedAt: scanner.startedAt,
            durationMs: durationMs,
            failureReason: failureReason
        )
    }

    private func workflowState(of workflow: WorkflowRecord, in record: SessionRecord) -> WorkflowState {
        let launch = launch(forRun: workflow.runId, in: record)
        let taskId = launch?.taskId ?? workflow.final?.taskId
        let notification = taskId.flatMap { record.workflowNotifications[$0] }?.notification
        let agentStates = workflow.keys.compactMap { key -> (WorkflowJournalEntry, SubagentState?)? in
            guard let entry = workflow.latest[key] else { return nil }
            return (entry, record.agents[entry.agentId].map { state(of: $0, in: record) })
        }
        let scriptPhases = workflow.final.flatMap { $0.phases.isEmpty ? nil : $0.phases } ?? workflow.scriptMeta?.phases ?? []
        var titles = scriptPhases.map(\.title)
        for phase in workflow.journalPhases where !titles.contains(phase) {
            titles.append(phase)
        }
        let details = Dictionary(scriptPhases.map { ($0.title, $0.detail) }, uniquingKeysWith: { first, _ in first })
        let phases = titles.map { title -> WorkflowPhase in
            let agents = agentStates.filter { $0.0.phase == title }.map { entry, state in
                WorkflowAgent(
                    agentId: entry.agentId,
                    label: entry.label,
                    status: state?.status ?? (workflow.results.contains(entry.agentId) ? .completed : .running),
                    activity: state?.activity,
                    durationMs: state?.durationMs
                )
            }
            return WorkflowPhase(title: title, detail: details[title] ?? nil, status: Self.phaseStatus(agents), agents: agents)
        }
        let status = workflow.final?.status ?? notification?.workflowStatus ?? .running
        let liveToolUses = agentStates.reduce(0) { $0 + ($1.1?.toolUses ?? 0) }
        return WorkflowState(
            runId: workflow.runId,
            sessionId: record.sessionId,
            toolUseId: launch?.toolUseId,
            name: launch?.workflowName ?? workflow.final?.workflowName ?? workflow.scriptMeta?.name,
            status: status,
            phases: phases,
            agentCount: workflow.final?.agentCount ?? (status == .running ? nil : notification?.agentCount) ?? workflow.keys.count,
            toolUses: workflow.final?.toolUses ?? liveToolUses,
            durationMs: status == .running ? nil : workflow.final?.durationMs ?? notification?.durationMs
        )
    }

    private static func phaseStatus(_ agents: [WorkflowAgent]) -> WorkflowPhaseStatus {
        guard !agents.isEmpty else { return .pending }
        if agents.contains(where: { $0.status == .running }) { return .running }
        if agents.contains(where: { $0.status == .failed || $0.status == .stopped }) { return .failed }
        return .completed
    }

    private func runningCount(in sessionId: String) -> Int {
        guard let record = sessions[sessionId] else { return 0 }
        var count = 0
        for file in record.agents.values where !(file.meta?.isSkill ?? false) {
            if let runId = file.runId {
                guard let workflow = record.workflows[runId], workflow.latestAgentIds.contains(file.agentId) else { continue }
            }
            if state(of: file, in: record).status == .running {
                count += 1
            }
        }
        return count
    }

    private func updateWatches(_ record: inout SessionRecord) {
        var targets: [String: DispatchSource.FileSystemEvent] = [:]
        if let directory = record.directory {
            let subagents = (directory as NSString).appendingPathComponent("subagents")
            let workflows = (subagents as NSString).appendingPathComponent("workflows")
            var directories = [subagents, workflows, (directory as NSString).appendingPathComponent("workflows")]
            directories += record.workflows.values.map(\.directory)
            let project = (directory as NSString).deletingLastPathComponent
            for path in directories {
                targets[Self.nearestExistingDirectory(from: path, stop: project)] = Self.directoryEvents
            }
            for file in record.agents.values where state(of: file, in: record).status == .running {
                targets[file.path] = Self.fileEvents
            }
            for workflow in record.workflows.values where workflowState(of: workflow, in: record).status == .running {
                targets[workflow.journalPath] = Self.fileEvents
            }
            if runningCount(in: record.sessionId) > 0 || record.workflows.values.contains(where: { workflowState(of: $0, in: record).status == .running }),
               let mainPath = record.mainPath {
                targets[mainPath] = Self.fileEvents
            }
        } else {
            for directory in locator.directoriesToWatch(for: TranscriptSession(sessionId: record.sessionId)) {
                targets[directory] = Self.directoryEvents
            }
        }
        for path in record.watches.keys where targets[path] == nil {
            record.watches[path]?.cancel()
            record.watches[path] = nil
        }
        let changes = changes
        let sessionId = record.sessionId
        for (path, events) in targets where record.watches[path] == nil {
            record.watches[path] = FileSystemWatch(path: path, events: events) {
                changes.yield(sessionId)
            }
        }
    }

    private func emitChanges(in sessionId: String) {
        guard let record = sessions[sessionId] else { return }
        var events: [SubagentEvent] = []
        for file in record.agents.values.sorted(by: { $0.agentId < $1.agentId }) where !(file.meta?.isSkill ?? false) {
            let current = state(of: file, in: record)
            if emittedAgents[file.agentId] != current {
                emittedAgents[file.agentId] = current
                events.append(.subagent(current))
            }
        }
        for workflow in record.workflows.values.sorted(by: { $0.runId < $1.runId }) {
            let current = workflowState(of: workflow, in: record)
            if emittedWorkflows[workflow.runId] != current {
                emittedWorkflows[workflow.runId] = current
                events.append(.workflow(current))
            }
        }
        let count = runningCount(in: sessionId)
        if emittedCounts[sessionId, default: 0] != count {
            emittedCounts[sessionId] = count
            events.append(.runningCount(sessionId: sessionId, count: count))
        }
        broadcast.publish(events)
    }

    static func metaPath(forTranscript path: String) -> String {
        (path as NSString).deletingPathExtension + ".meta.json"
    }

    private static func readScript(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: scriptLimit) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func entries(of directory: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory))?.sorted() ?? []
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private static func nearestExistingDirectory(from path: String, stop: String) -> String {
        var current = path
        while !isDirectory(current), current != stop, current != "/", !current.isEmpty {
            current = (current as NSString).deletingLastPathComponent
        }
        return current
    }
}
