import Foundation
import MochaProtocol
import MochaTestSupport
import Synchronization
import Testing
@testable import MochaDaemonCore

struct SubagentProjects {
    static let backgroundSession = "4905c442-7092-5f7c-ab64-f812dec40387"
    static let workflowSession = "74fb34b2-7495-51eb-abc8-1140004fdc00"

    let root: URL
    let project: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "mocha-subagents-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = root.appending(path: "-Users-dev-projects-demo-app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    var rootPath: String {
        root.path(percentEncoded: false)
    }

    func install(fixture name: String, session sessionId: String) throws {
        let source = TranscriptFixtures.directory
        try FileManager.default.copyItem(at: source.appending(path: "\(name).jsonl"), to: project.appending(path: "\(sessionId).jsonl"))
        try FileManager.default.copyItem(at: source.appending(path: name, directoryHint: .isDirectory), to: sessionDirectory(sessionId))
    }

    func sessionDirectory(_ sessionId: String) -> URL {
        project.appending(path: sessionId, directoryHint: .isDirectory)
    }

    func subagentsDirectory(_ sessionId: String) -> URL {
        sessionDirectory(sessionId).appending(path: "subagents", directoryHint: .isDirectory)
    }

    func append(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

enum SubagentEventWaiter {
    static func first(
        _ stream: AsyncStream<SubagentEvent>,
        timeout: Duration = .seconds(5),
        where predicate: @escaping @Sendable (SubagentEvent) -> Bool
    ) async -> SubagentEvent? {
        await withTaskGroup(of: SubagentEvent?.self) { group in
            group.addTask {
                for await event in stream where predicate(event) {
                    return event
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

@Suite struct SubagentStoreTests {
    @Test func backgroundOutcomesFollowTheSignals() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "subagents-background", session: SubagentProjects.backgroundSession)
        let store = SubagentStore(projectsRoot: projects.rootPath)
        await store.observe(sessions: [SubagentProjects.backgroundSession])

        let failed = try #require(await store.state("a2222222222222222"))
        #expect(failed.status == .failed)
        #expect(failed.failureReason == "API Error: 529 Overloaded. Try again in a few moments.")
        #expect(failed.durationMs != nil)
        #expect(await store.state("a3333333333333333")?.status == .stopped)
        #expect(await store.state("a4444444444444444")?.status == .completed)
        let nested = try #require(await store.state("a6666666666666666"))
        #expect(nested.parentAgentId == "a1111111111111111")
        #expect(nested.agentType == "code-reviewer")
        #expect(await store.state("a7777777777777777") == nil)
        #expect(await store.runningCount(session: SubagentProjects.backgroundSession) == 0)

        let list = await store.subagents(session: SubagentProjects.backgroundSession)
        let parentIndex = try #require(list.firstIndex { $0.agentId == "a1111111111111111" })
        let children = list.enumerated().filter { $0.element.parentAgentId == "a1111111111111111" }.map(\.offset)
        #expect(!children.isEmpty)
        #expect(children.allSatisfy { $0 > parentIndex })
        #expect(Set(list.map(\.agentId)).isSuperset(of: ["a1111111111111111", "a2222222222222222", "a3333333333333333"]))
    }

    @Test func appendedToolUseChangesTheActivity() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        let sessionId = UUID().uuidString.lowercased()
        let subagents = projects.subagentsDirectory(sessionId)
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data().write(to: projects.project.appending(path: "\(sessionId).jsonl"))
        let agentId = "a00000000000000aa"
        let transcript = subagents.appending(path: "agent-\(agentId).jsonl")
        try Data((SubagentLines.task("Rodar os testes") + "\n").utf8).write(to: transcript)

        let store = SubagentStore(projectsRoot: projects.rootPath)
        let events = store.events()
        await store.observe(sessions: [sessionId])
        #expect(await store.state(agentId)?.status == .running)
        #expect(await store.runningCount(session: sessionId) == 1)

        try projects.append(SubagentLines.toolUse(id: "toolu_1", name: "Bash", command: "swift test"), to: transcript)
        let changed = await SubagentEventWaiter.first(events) { event in
            guard case .subagent(let state) = event else { return false }
            return state.agentId == agentId && state.toolUses == 1
        }
        guard case .subagent(let state) = changed else {
            Issue.record("no event for the appended tool_use")
            return
        }
        #expect(state.activity == ToolActivity(toolName: "Bash", summary: "swift test", status: .running))

        let meta = subagents.appending(path: "agent-\(agentId).meta.json")
        try Data(#"{"agentType":"general-purpose","description":"Rodar testes","toolUseId":"toolu_parent"}"#.utf8).write(to: meta)
        let described = await SubagentEventWaiter.first(events) { event in
            guard case .subagent(let state) = event else { return false }
            return state.description == "Rodar testes"
        }
        #expect(described != nil)

        let replacement = subagents.appending(path: "replacement.tmp")
        try Data(#"{"agentType":"general-purpose","description":"Rodar testes","toolUseId":"toolu_parent","stoppedByUser":true}"#.utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(meta, withItemAt: replacement)
        let stopped = await SubagentEventWaiter.first(events) { event in
            guard case .subagent(let state) = event else { return false }
            return state.status == .stopped
        }
        #expect(stopped != nil)
        let zero = await SubagentEventWaiter.first(events) { event in
            guard case .runningCount(let session, 0) = event else { return false }
            return session == sessionId
        }
        #expect(zero != nil)
    }

    @Test func workflowPhasesAgentsAndFinalState() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "workflow", session: SubagentProjects.workflowSession)
        let store = SubagentStore(projectsRoot: projects.rootPath)
        await store.observe(sessions: [SubagentProjects.workflowSession])

        let workflow = try #require(await store.workflow("wf_0a1b2c3d-4e5"))
        #expect(workflow.status == .completed)
        #expect(workflow.name == "demo-wave")
        #expect(workflow.agentCount == 2)
        #expect(workflow.phases.map(\.title) == ["Implementar", "Verificar"])
        #expect(workflow.phases.map(\.detail) == ["Um agente por tarefa", "Um agente verificador"])
        #expect(workflow.phases.map(\.status) == [.completed, .completed])
        #expect(workflow.phases.last?.agents.map(\.agentId) == ["abbbbbbbbbbbbbbbb"])
        #expect(workflow.toolUseId != nil)
        #expect(await store.subagents(session: SubagentProjects.workflowSession).isEmpty)
        #expect(await store.runningCount(session: SubagentProjects.workflowSession) == 0)
    }

    @Test func workflowWithoutFinalStateUsesTheScriptAndTheJournal() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "workflow", session: SubagentProjects.workflowSession)
        let final = projects.sessionDirectory(SubagentProjects.workflowSession).appending(path: "workflows/wf_0a1b2c3d-4e5.json")
        try FileManager.default.removeItem(at: final)
        let store = SubagentStore(projectsRoot: projects.rootPath)
        await store.observe(sessions: [SubagentProjects.workflowSession])

        let workflow = try #require(await store.workflow("wf_0a1b2c3d-4e5"))
        #expect(workflow.phases.map(\.title) == ["Implementar", "Verificar"])
        #expect(workflow.agentCount == 2)
        #expect(workflow.phases.last?.agents.map(\.agentId) == ["abbbbbbbbbbbbbbbb"])
        #expect(workflow.status == .completed)
    }

    @Test func workflowPhasesComeFromTheScriptPathOrFallBackToTheJournal() async throws {
        for (script, expected) in [
            ("export const meta = { name: 'onda', phases: [{ title: 'Planejar' }, { title: 'Implementar' }, { title: 'Verificar' }] }", ["Planejar", "Implementar", "Verificar"]),
            ("export const meta = { phases: [{ title: `x${y}` }] }", ["Implementar", "Verificar"]),
        ] {
            let projects = try SubagentProjects()
            defer { projects.remove() }
            try projects.install(fixture: "workflow", session: SubagentProjects.workflowSession)
            let session = projects.sessionDirectory(SubagentProjects.workflowSession)
            try FileManager.default.removeItem(at: session.appending(path: "workflows/wf_0a1b2c3d-4e5.json"))
            let scriptURL = session.appending(path: "workflows/scripts/onda-wf_0a1b2c3d-4e5.js")
            try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(script.utf8).write(to: scriptURL)
            let mainURL = projects.project.appending(path: "\(SubagentProjects.workflowSession).jsonl")
            let lines = try String(contentsOf: mainURL, encoding: .utf8).split(separator: "\n").map { line -> String in
                guard line.contains("\"name\":\"Workflow\""),
                      var object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      var message = object["message"] as? [String: Any],
                      var content = message["content"] as? [[String: Any]] else {
                    return String(line)
                }
                for index in content.indices where content[index]["name"] as? String == "Workflow" {
                    content[index]["input"] = ["args": [:], "scriptPath": scriptURL.path(percentEncoded: false)]
                }
                message["content"] = content
                object["message"] = message
                return SubagentLines.json(object)
            }
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: mainURL)
            let store = SubagentStore(projectsRoot: projects.rootPath)
            await store.observe(sessions: [SubagentProjects.workflowSession])
            let workflow = try #require(await store.workflow("wf_0a1b2c3d-4e5"))
            #expect(workflow.phases.map(\.title) == expected)
            #expect(workflow.phases.first { $0.title == "Planejar" }.map(\.status) ?? .pending == .pending)
        }
    }

    @Test func interimNotificationKeepsTheAgentRunningUntilTheFinalOne() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        let sessionId = UUID().uuidString.lowercased()
        let agentId = "a00000000000000bb"
        let subagents = projects.subagentsDirectory(sessionId)
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        let transcript = subagents.appending(path: "agent-\(agentId).jsonl")
        let finished = SubagentLines.json([
            "type": "assistant", "isSidechain": true, "uuid": UUID().uuidString, "timestamp": "2026-09-27T01:00:10.000Z",
            "message": ["role": "assistant", "model": "claude-opus-5-5", "stop_reason": "end_turn", "content": [["type": "text", "text": "Pronto."]]],
        ])
        try Data((SubagentLines.task("Rodar") + "\n" + finished + "\n").utf8).write(to: transcript)
        func enqueue(_ note: String?, at time: String, usage: String = "") -> String {
            let noteTag = note.map { "<note>\($0)</note>" } ?? ""
            return SubagentLines.json([
                "type": "queue-operation", "operation": "enqueue", "timestamp": time,
                "content": "<task-notification>\n<task-id>\(agentId)</task-id>\n<status>completed</status>\n<summary>Agent \"Rodar\" completed</summary>\(noteTag)\(usage)\n</task-notification>",
            ])
        }
        let main = projects.project.appending(path: "\(sessionId).jsonl")
        try Data((enqueue("Agent stopped with background work of its own still running.", at: "2026-09-27T01:00:11.000Z") + "\n").utf8).write(to: main)

        let store = SubagentStore(projectsRoot: projects.rootPath)
        let events = store.events()
        await store.observe(sessions: [sessionId])
        #expect(await store.state(agentId)?.status == .running)
        #expect(await store.runningCount(session: sessionId) == 1)

        try projects.append(enqueue(nil, at: "2026-09-27T01:02:00.000Z", usage: "<usage><tool_uses>4</tool_uses><duration_ms>120000</duration_ms></usage>"), to: main)
        let completed = await SubagentEventWaiter.first(events) { event in
            guard case .subagent(let state) = event else { return false }
            return state.agentId == agentId && state.status == .completed
        }
        guard case .subagent(let state) = completed else {
            Issue.record("the final notification did not complete the agent")
            return
        }
        #expect(state.durationMs == 120000)
    }

    @Test func symlinkedWorkflowIsCountedOnce() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "workflow", session: SubagentProjects.workflowSession)
        let workflows = projects.subagentsDirectory(SubagentProjects.workflowSession).appending(path: "workflows")
        try FileManager.default.createSymbolicLink(
            at: workflows.appending(path: "wf_ffffffff-fff"),
            withDestinationURL: workflows.appending(path: "wf_0a1b2c3d-4e5")
        )
        let store = SubagentStore(projectsRoot: projects.rootPath)
        await store.observe(sessions: [SubagentProjects.workflowSession])
        #expect(await store.workflow("wf_0a1b2c3d-4e5") != nil)
        #expect(await store.workflow("wf_ffffffff-fff") == nil)
    }

    @Test func firstReadOfTheMainTranscriptStopsAtEightMegabytes() async throws {
        let big = TranscriptFixtures.bigFixture
        guard FileManager.default.fileExists(atPath: big.path(percentEncoded: false)) else { return }
        let projects = try SubagentProjects()
        defer { projects.remove() }
        let sessionId = UUID().uuidString.lowercased()
        try FileManager.default.createSymbolicLink(at: projects.project.appending(path: "\(sessionId).jsonl"), withDestinationURL: big)
        let counter = Mutex(0)
        let store = SubagentStore(projectsRoot: projects.rootPath, hooks: SubagentStoreHooks(mainBytesRead: { _, count in
            counter.withLock { $0 += count }
        }))
        await store.observe(sessions: [sessionId])
        let read = counter.withLock { $0 }
        #expect(read > 0)
        #expect(read <= Int(SubagentStore.mainScanLimit))
    }

    @Test func transcriptResolvesAgentAndWorkflowFiles() async throws {
        let projects = try SubagentProjects()
        defer { projects.remove() }
        try projects.install(fixture: "subagents-background", session: SubagentProjects.backgroundSession)
        try projects.install(fixture: "workflow", session: SubagentProjects.workflowSession)
        let store = SubagentStore(projectsRoot: projects.rootPath)

        let fork = try #require(await store.transcript(session: SubagentProjects.backgroundSession, agentId: "a4444444444444444"))
        #expect(fork.forkToolUseId == "toolu_01FIXTUREDAGENT00000000001")
        #expect(fork.path.hasSuffix("agent-a4444444444444444.jsonl"))
        let plain = try #require(await store.transcript(session: SubagentProjects.backgroundSession, agentId: "a6666666666666666"))
        #expect(plain.forkToolUseId == nil)
        let workflowAgent = await store.transcript(session: SubagentProjects.workflowSession, agentId: "a8888888888888888")
        #expect(workflowAgent?.path.contains("wf_0a1b2c3d-4e5") == true)
        #expect(await store.transcript(session: SubagentProjects.backgroundSession, agentId: "a0000000000000000") == nil)
        #expect(await store.transcript(session: SubagentProjects.backgroundSession, agentId: "../x") == nil)
    }
}

enum SubagentLines {
    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func task(_ text: String) -> String {
        json([
            "type": "user", "parentUuid": NSNull(), "isSidechain": true, "uuid": UUID().uuidString,
            "timestamp": "2026-09-27T01:00:00.000Z", "message": ["role": "user", "content": text],
        ])
    }

    static func toolUse(id: String, name: String, command: String) -> String {
        json([
            "type": "assistant", "isSidechain": true, "uuid": UUID().uuidString, "timestamp": "2026-09-27T01:00:05.000Z",
            "cwd": "/Users/dev/projects/demo-app",
            "message": [
                "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "tool_use",
                "content": [["type": "tool_use", "id": id, "name": name, "input": ["command": command]]],
            ],
        ])
    }
}
