import Foundation
import MochaHerdr
import Testing
@testable import MochaDaemonCore

struct CodexLab: Sendable {
    let directory: URL
    let pane: String
    let version: String

    static let current: CodexLab? = {
        let environment = ProcessInfo.processInfo.environment
        let value = { (key: String) in environment[key].flatMap { $0.isEmpty ? nil : $0 } }
        guard environment["MOCHA_INTEGRATION"] == "1",
              let directory = value("MOCHA_CODEX_LAB"),
              let pane = value("MOCHA_CODEX_LAB_PANE"),
              let version = value("MOCHA_CODEX_VERSION") else { return nil }
        return CodexLab(directory: URL(filePath: directory, directoryHint: .isDirectory), pane: pane, version: version)
    }()

    static var isEnabled: Bool { current != nil }

    var socketPath: String { path("app-server.sock") }
    var codexHome: String { path("codex-home") }
    var workDirectory: String { path("work") }
    var stableSchema: URL { directory.appending(path: "schema/stable", directoryHint: .isDirectory) }
    var experimentalSchema: URL { directory.appending(path: "schema/experimental", directoryHint: .isDirectory) }
    var schemaSnapshot: URL { directory.appending(path: "schema-methods.json") }

    static func standardized(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
    }

    func withServer<Value: Sendable>(_ body: (CodexAppServer, OrderedJSON) async throws -> Value) async throws -> Value {
        let server = CodexAppServer(socketPath: socketPath, requestTimeout: .seconds(10))
        do {
            let initialize = try await server.connect()
            let value = try await body(server, initialize)
            await server.shutdown()
            return value
        } catch {
            await server.shutdown()
            throw error
        }
    }

    private func path(_ name: String) -> String {
        Self.standardized(directory.appending(path: name).path(percentEncoded: false))
    }
}

enum CodexLabError: Error, CustomStringConvertible {
    case disabled
    case timeout(String)
    case missing(String)
    case request(String, String)

    var description: String {
        switch self {
        case .disabled: "lab do Codex desligado"
        case .timeout(let what): "tempo esgotado esperando \(what)"
        case .missing(let what): "faltou \(what)"
        case .request(let method, let error): "\(method) falhou: \(error)"
        }
    }
}

struct CodexLabEvent: Sendable {
    let method: String
    let params: OrderedJSON
}

actor CodexLabRecorder {
    private(set) var events: [CodexLabEvent] = []

    func record(_ event: CodexLabEvent) {
        events.append(event)
    }

    func first(where matches: @Sendable (CodexLabEvent) -> Bool) -> CodexLabEvent? {
        events.first(where: matches)
    }

    func wait(
        for description: String,
        timeout: Duration,
        where matches: @escaping @Sendable (CodexLabEvent) -> Bool
    ) async throws -> CodexLabEvent {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let event = first(where: matches) { return event }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CodexLabError.timeout(description)
    }
}

struct CodexLabCycle: Sendable {
    static let prompt = "Responda só com o resultado de 6 × 7, sem mais nada."
    static let answer = "42"
    static let shared = Task<CodexLabCycle, any Error> {
        guard let lab = CodexLab.current else { throw CodexLabError.disabled }
        return try await run(in: lab)
    }

    let threadId: String
    let events: [CodexLabEvent]
    let responses: [String: OrderedJSON]
    let failures: [String: String]
    let screens: [String: String]

    func events(_ method: String) -> [CodexLabEvent] {
        events.filter { $0.method == method && $0.params["threadId"].map { $0.stringValue == threadId } ?? true }
    }

    static func showsAnswer(_ screen: String) -> Bool {
        screen.split(separator: "\n").contains { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) == answer }
    }

    static func showsPlanMode(_ screen: String) -> Bool {
        screen.localizedCaseInsensitiveContains("plan mode")
    }

    private static func run(in lab: CodexLab) async throws -> CodexLabCycle {
        let server = CodexAppServer(socketPath: lab.socketPath)
        let recorder = CodexLabRecorder()
        let initialize = try await server.connect()
        let stream = server.events
        let consumer = Task {
            for await event in stream {
                await recorder.record(CodexLabEvent(method: event.method, params: event.params))
            }
        }
        do {
            var run = CodexLabCycleRun(lab: lab, server: server, recorder: recorder)
            run.responses["initialize"] = initialize
            try await run.start()
            await run.exerciseSettings()
            await run.readHistory()
            consumer.cancel()
            await server.shutdown()
            return CodexLabCycle(
                threadId: run.threadId,
                events: await recorder.events,
                responses: run.responses,
                failures: run.failures,
                screens: run.screens
            )
        } catch {
            consumer.cancel()
            await server.shutdown()
            throw error
        }
    }
}

private struct CodexLabCycleRun {
    let lab: CodexLab
    let server: CodexAppServer
    let recorder: CodexLabRecorder
    let herdr = HerdrClient(configuration: HerdrClientConfiguration(socketPath: HerdrSocketPath.resolve()))
    var threadId = ""
    var responses: [String: OrderedJSON] = [:]
    var failures: [String: String] = [:]
    var screens: [String: String] = [:]

    init(lab: CodexLab, server: CodexAppServer, recorder: CodexLabRecorder) {
        self.lab = lab
        self.server = server
        self.recorder = recorder
    }

    private var thread: OrderedJSON { .object([.init("threadId", .string(threadId))]) }

    mutating func start() async throws {
        try await herdr.agentStart(
            name: "mocha-lab-codex",
            kind: HerdrBridge.codexAgentKind,
            paneId: lab.pane,
            args: HerdrBridge.codexArguments(remote: "unix://\(lab.socketPath)", directory: lab.workDirectory),
            timeout: .seconds(30)
        )
        let work = lab.workDirectory
        let started = try await recorder.wait(for: "thread/started do TUI em \(work)", timeout: .seconds(30)) { event in
            guard event.method == "thread/started", let thread = event.params["thread"] else { return false }
            return thread["cwd"]?.stringValue.map(CodexLab.standardized) == work && thread["ephemeral"]?.boolValue == false
        }
        guard let id = started.params["thread"]?["id"]?.stringValue else { throw CodexLabError.missing("o id do thread/started") }
        threadId = id
        try await require("thread/loaded/list", .object([]))
        let input = try CodexService.promptInput(CodexLabCycle.prompt, uploadsDirectory: lab.directory)
        try await require("turn/start", thread.setting("input", to: .array(input)))
        var attempts = 1
        while await call("thread/resume", thread.setting("excludeTurns", to: .bool(true))) == nil {
            guard attempts < 20 else { throw CodexLabError.request("thread/resume", failures["thread/resume"] ?? "") }
            if attempts == 1 {
                print("ciclo: o thread/resume logo depois do turn/start falhou: \(failures["thread/resume"] ?? "")")
            }
            attempts += 1
            try await Task.sleep(for: .milliseconds(250))
        }
        failures["thread/resume"] = nil
        if attempts > 1 {
            print("ciclo: o thread/resume passou na tentativa \(attempts), como o connectLoop do daemon faria")
        }
        let threadId = id
        _ = try await recorder.wait(for: "turn/completed", timeout: .seconds(120)) {
            $0.method == "turn/completed" && $0.params["threadId"]?.stringValue == threadId
        }
        screens["turn"] = await screen(until: CodexLabCycle.showsAnswer)
    }

    mutating func exerciseSettings() async {
        guard let models = await call("model/list", .object([])) else { return }
        let resume = responses["thread/resume"] ?? .null
        let model = resume["model"]?.stringValue ?? ""
        let effort = resume["reasoningEffort"] ?? .null
        let mode = { (name: String) in
            OrderedJSON.object([
                .init("mode", .string(name)),
                .init("settings", .object([
                    .init("model", .string(model)),
                    .init("reasoning_effort", effort),
                    .init("developer_instructions", .null),
                ])),
            ])
        }
        guard await update("plan", thread.setting("collaborationMode", to: mode("plan")), { $0["collaborationMode"]?["mode"]?.stringValue == "plan" }) else { return }
        screens["plan"] = await screen(until: CodexLabCycle.showsPlanMode)
        guard await update("default", thread.setting("collaborationMode", to: mode("default")), { $0["collaborationMode"]?["mode"]?.stringValue == "default" }) else { return }
        let target = models["data"]?.arrayValue?
            .first { $0["model"]?.stringValue == model || $0["id"]?.stringValue == model }?["defaultReasoningEffort"]?.stringValue ?? "low"
        _ = await update("effort", thread.setting("effort", to: .string(target)), { $0["effort"]?.stringValue == target })
    }

    mutating func readHistory() async {
        _ = await call("thread/read", thread.setting("includeTurns", to: .bool(false)))
        _ = await call("thread/turns/list", thread
            .setting("itemsView", to: .string("full"))
            .setting("sortDirection", to: .string("desc"))
            .setting("limit", to: .number("20")))
        _ = await call("thread/items/list", thread
            .setting("limit", to: .number("20"))
            .setting("sortDirection", to: .string("desc")))
        _ = await call("account/read", .object([]))
        _ = await call("account/rateLimits/read", .object([]))
        _ = await call("thread/unsubscribe", thread)
    }

    private mutating func require(_ method: String, _ params: OrderedJSON) async throws {
        guard await call(method, params) != nil else { throw CodexLabError.request(method, failures[method] ?? "") }
    }

    private mutating func call(_ method: String, _ params: OrderedJSON) async -> OrderedJSON? {
        do {
            let result = try await server.request(method, params: params)
            responses[method] = result
            return result
        } catch {
            failures[method] = String(describing: error)
            return nil
        }
    }

    private mutating func update(
        _ label: String,
        _ params: OrderedJSON,
        _ applied: @escaping @Sendable (OrderedJSON) -> Bool
    ) async -> Bool {
        guard await call("thread/settings/update", params) != nil else {
            failures["thread/settings/update \(label)"] = failures["thread/settings/update"]
            return false
        }
        let threadId = threadId
        do {
            _ = try await recorder.wait(for: "thread/settings/updated \(label)", timeout: .seconds(10)) { event in
                event.method == "thread/settings/updated" && event.params["threadId"]?.stringValue == threadId
                    && applied(event.params["threadSettings"] ?? .null)
            }
            return true
        } catch {
            failures["thread/settings/updated \(label)"] = String(describing: error)
            return false
        }
    }

    private func screen(until matches: (String) -> Bool) async -> String {
        var screen = ""
        for _ in 0..<50 {
            screen = (try? await herdr.paneRead(paneId: lab.pane, source: .visible).text) ?? screen
            if matches(screen) { return screen }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return screen
    }
}
