#!/usr/bin/env swift
import Foundation

struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double(next() % 1_000_000) / 1_000_000 < probability
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[Int(next() % UInt64(values.count))]
    }
}

indirect enum JSON {
    case string(String)
    case raw(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSON])
    case object([(String, JSON)])
}

func escape(_ text: String, into out: inout String) {
    out.append("\"")
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": out.append("\\\"")
        case "\\": out.append("\\\\")
        case "\n": out.append("\\n")
        case "\r": out.append("\\r")
        case "\t": out.append("\\t")
        default:
            if scalar.value < 0x20 {
                out.append(String(format: "\\u%04x", scalar.value))
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    out.append("\"")
}

func encode(_ value: JSON, into out: inout String) {
    switch value {
    case .string(let text): escape(text, into: &out)
    case .raw(let text):
        out.append("\"")
        out.append(text)
        out.append("\"")
    case .int(let number): out.append(String(number))
    case .double(let number): out.append(String(number))
    case .bool(let flag): out.append(flag ? "true" : "false")
    case .null: out.append("null")
    case .array(let values):
        out.append("[")
        for (index, element) in values.enumerated() {
            if index > 0 { out.append(",") }
            encode(element, into: &out)
        }
        out.append("]")
    case .object(let fields):
        out.append("{")
        for (index, field) in fields.enumerated() {
            if index > 0 { out.append(",") }
            escape(field.0, into: &out)
            out.append(":")
            encode(field.1, into: &out)
        }
        out.append("}")
    }
}

struct Generator {
    static let words = [
        "demo-app", "login", "senha", "teste", "build", "rota", "componente", "estado", "cache", "fila",
        "usuário", "sessão", "token", "erro", "ajuste", "função", "arquivo", "módulo", "tela", "botão",
        "the", "request", "response", "handler", "config", "value", "index", "render", "update", "commit",
        "sync", "async", "await", "return", "export", "import", "const", "let", "struct", "enum",
    ]
    static let base62 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    static let base64 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    static let cwd = "/Users/dev/projects/demo-app"

    var random = SplitMix64(state: 0x4D6F_6368_6153_3101)
    let sessionId: String
    var clock: Double = 1_790_348_400_000
    var parent: String?
    var promptId = ""
    var messageId = ""
    var blockIndex = 0
    var turn = 0
    var compacted = false
    var buffer = ""
    var lineCount = 0
    let formatter: ISO8601DateFormatter

    init() {
        var seed = SplitMix64(state: 0x5E55_1011)
        sessionId = Generator.uuid(&seed)
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    static func uuid(_ random: inout SplitMix64) -> String {
        let hex = Array("0123456789abcdef")
        var text = ""
        for index in 0..<32 {
            if [8, 12, 16, 20].contains(index) { text.append("-") }
            if index == 12 {
                text.append("4")
            } else if index == 16 {
                text.append(hex[8 + Int(random.next() % 4)])
            } else {
                text.append(hex[Int(random.next() % 16)])
            }
        }
        return text
    }

    mutating func newUUID() -> String { Generator.uuid(&random) }

    mutating func token(_ count: Int, alphabet: [Character] = Generator.base62) -> String {
        var text = ""
        text.reserveCapacity(count)
        for _ in 0..<count { text.append(alphabet[Int(random.next() % UInt64(alphabet.count))]) }
        return text
    }

    mutating func timestamp(advance milliseconds: Int) -> String {
        clock += Double(milliseconds)
        return formatter.string(from: Date(timeIntervalSince1970: clock / 1000))
    }

    mutating func prose(_ approximateBytes: Int, lineBreakEvery: Int = 14) -> String {
        var text = ""
        text.reserveCapacity(approximateBytes + 16)
        var count = 0
        while text.utf8.count < approximateBytes {
            text.append(random.pick(Generator.words))
            count += 1
            text.append(count % lineBreakEvery == 0 ? "\\n" : " ")
        }
        return text
    }

    func tail(stale: Bool = true, slug: Bool = false) -> [(String, JSON)] {
        var fields: [(String, JSON)] = []
        if stale { fields.append(("session_id", .string(sessionId))) }
        fields.append(contentsOf: [
            ("userType", .string("external")), ("entrypoint", .string("cli")), ("cwd", .string(Generator.cwd)),
            ("sessionId", .string(sessionId)), ("version", .string("2.1.282")), ("gitBranch", .string("main")),
        ])
        if slug { fields.append(("slug", .string("quiet-demo-otter"))) }
        return fields
    }

    mutating func emit(_ fields: [(String, JSON)]) {
        encode(.object(fields), into: &buffer)
        buffer.append("\n")
        lineCount += 1
    }

    mutating func metadataTail(prompt: String) {
        emit([("type", .string("last-prompt")), ("lastPrompt", .string(prompt)), ("leafUuid", .string(parent ?? "")), ("sessionId", .string(sessionId))])
        emit([("type", .string("ai-title")), ("aiTitle", .string("Evoluir o demo-app")), ("sessionId", .string(sessionId))])
        emit([("type", .string("mode")), ("mode", .string("normal")), ("sessionId", .string(sessionId))])
        emit([("type", .string("permission-mode")), ("permissionMode", .string("auto")), ("sessionId", .string(sessionId))])
        emit([("type", .string("atis-latch")), ("atis", .string("")), ("sessionId", .string(sessionId))])
    }

    mutating func prompt(text: String, images: Int) {
        let id = newUUID()
        promptId = newUUID()
        emit([("type", .string("file-history-snapshot")), ("messageId", .string(id)),
              ("snapshot", .object([("messageId", .string(id)), ("trackedFileBackups", .object([])), ("timestamp", .string(timestamp(advance: 1)))])),
              ("isSnapshotUpdate", .bool(false))])
        var content: JSON = .raw(text)
        if images > 0 {
            var blocks: [JSON] = [.object([("type", .string("text")), ("text", .raw(text))])]
            for _ in 0..<images {
                let data = token(random.int(150_000...450_000), alphabet: Generator.base64)
                blocks.append(.object([("type", .string("image")),
                                       ("source", .object([("type", .string("base64")), ("media_type", .string("image/png")), ("data", .raw(data))]))]))
            }
            content = .array(blocks)
        }
        var fields: [(String, JSON)] = [
            ("parentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)), ("promptId", .string(promptId)),
            ("type", .string("user")), ("message", .object([("role", .string("user")), ("content", content)])),
            ("uuid", .string(id)), ("timestamp", .string(timestamp(advance: random.int(20_000...600_000)))),
            ("permissionMode", .string("auto")), ("origin", .object([("kind", .string("human"))])),
            ("promptSource", .string("typed")), ("turnOrigin", .string("human")),
        ]
        if images > 0 { fields.append(("imagePasteIds", .array((1...images).map { .int($0) }))) }
        fields.append(contentsOf: tail(stale: false))
        emit(fields)
        parent = id
    }

    mutating func attachment() {
        let id = newUUID()
        let kind = random.pick(["total_tokens_reminder", "batching_reminder_sent", "bash_output_audience_note", "deferred_tools_record", "edited_text_file", "environment"])
        let body = prose(random.int(400...5_000))
        emit([("parentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)),
              ("attachment", .object([("type", .string(kind)), ("content", .raw(body))])), ("type", .string("attachment")),
              ("uuid", .string(id)), ("timestamp", .string(timestamp(advance: random.int(1...40)))),
              ("rendered", .array([.object([("content", .raw("<system-reminder>" + body + "</system-reminder>"))])]))] + tail())
        parent = id
    }

    func usage() -> JSON {
        .object([("input_tokens", .int(12)), ("cache_creation_input_tokens", .int(1_200)), ("cache_read_input_tokens", .int(80_000)),
                 ("output_tokens", .int(240)), ("service_tier", .string("standard"))])
    }

    mutating func assistant(block: JSON, stopReason: String?, wireInput: (String, JSON)? = nil) {
        let id = newUUID()
        var fields: [(String, JSON)] = [
            ("parentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)),
            ("message", .object([("model", .string("claude-opus-5-5")), ("id", .string(messageId)), ("type", .string("message")),
                                 ("role", .string("assistant")), ("content", .array([block])), ("container", .null),
                                 ("stop_reason", stopReason.map { .string($0) } ?? .null), ("stop_sequence", .null),
                                 ("usage", usage())])),
        ]
        if let wireInput { fields.append(("wireToolInputs", .object([wireInput]))) }
        fields.append(contentsOf: [("apiBlockIndex", .int(blockIndex)), ("requestId", .string("req_01" + token(22))),
                                   ("type", .string("assistant")), ("uuid", .string(id)),
                                   ("timestamp", .string(timestamp(advance: random.int(300...9_000)))),
                                   ("effort", .string("high")), ("perTurnEffort", .null)])
        fields.append(contentsOf: tail(slug: true))
        emit(fields)
        blockIndex += 1
        parent = id
    }

    mutating func startMessage() {
        messageId = "msg_01" + token(22)
        blockIndex = 0
    }

    mutating func thinking() {
        let text = random.chance(0.12) ? prose(random.int(600...3_000)) : ""
        let signature = token(random.int(1_500...6_000), alphabet: Generator.base64)
        assistant(block: .object([("type", .string("thinking")), ("thinking", .raw(text)), ("signature", .raw(signature))]), stopReason: "tool_use")
    }

    mutating func toolRound() {
        let name = random.pick(["Bash", "Bash", "Bash", "Read", "Edit", "Write", "Agent", "WebFetch"])
        let toolId = "toolu_01" + token(22)
        var input: JSON
        switch name {
        case "Bash":
            input = .object([("command", .string("npm run " + random.pick(["test", "lint", "build"]) + " -- --filter " + random.pick(Generator.words))),
                             ("description", .string("Roda uma etapa do projeto"))])
        case "Read":
            input = .object([("file_path", .string(Generator.cwd + "/src/" + random.pick(Generator.words) + ".ts"))])
        case "Edit":
            input = .object([("file_path", .string(Generator.cwd + "/src/" + random.pick(Generator.words) + ".ts")),
                             ("old_string", .raw(prose(random.int(100...1_500)))), ("new_string", .raw(prose(random.int(100...2_500)))),
                             ("replace_all", .bool(false))])
        case "Write":
            input = .object([("file_path", .string(Generator.cwd + "/src/" + random.pick(Generator.words) + ".ts")),
                             ("content", .raw(prose(random.int(500...6_000))))])
        case "Agent":
            input = .object([("description", .string("Investigar " + random.pick(Generator.words))), ("subagent_type", .string("Explore")),
                             ("prompt", .raw(prose(random.int(300...1_500))))])
        default:
            input = .object([("url", .string("https://example.com/docs/" + random.pick(Generator.words))), ("prompt", .string("Resuma a página"))])
        }
        assistant(block: .object([("type", .string("tool_use")), ("id", .string(toolId)), ("name", .string(name)), ("input", input),
                                  ("caller", .object([("type", .string("direct"))]))]),
                  stopReason: "tool_use", wireInput: (toolId, input))
        let source = parent ?? ""
        let roll = random.int(1...100)
        let size = roll <= 60 ? random.int(200...2_000) : (roll <= 90 ? random.int(5_000...20_000) : random.int(40_000...80_000))
        let output = prose(size, lineBreakEvery: 9)
        let failed = random.chance(0.03)
        var block: [(String, JSON)] = [("tool_use_id", .string(toolId)), ("type", .string("tool_result")),
                                       ("content", .raw(failed ? "Exit code 1\\n" + output : output))]
        if name == "Bash" { block.append(("is_error", .bool(failed))) }
        let resultId = newUUID()
        var toolUseResult: JSON = .object([("stdout", .raw(output)), ("stderr", .string("")), ("interrupted", .bool(false)),
                                           ("isImage", .bool(false)), ("noOutputExpected", .bool(false))])
        if name != "Bash" { toolUseResult = .object([("type", .string("text")), ("filePath", .string(Generator.cwd + "/src/app.ts"))]) }
        emit([("parentUuid", .string(source)), ("isSidechain", .bool(false)), ("promptId", .string(promptId)), ("type", .string("user")),
              ("message", .object([("role", .string("user")), ("content", .array([.object(block)]))])),
              ("uuid", .string(resultId)), ("timestamp", .string(timestamp(advance: random.int(50...30_000)))),
              ("toolUseResult", toolUseResult), ("sourceToolAssistantUUID", .string(source))] + tail())
        parent = resultId
    }

    mutating func system(_ subtype: String, _ fields: [(String, JSON)], advance: Int = 20) {
        let id = newUUID()
        emit([("parentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)), ("type", .string("system")),
              ("subtype", .string(subtype))] + fields + [("timestamp", .string(timestamp(advance: advance))), ("uuid", .string(id)),
                                                         ("isMeta", .bool(false))] + tail(stale: false))
        parent = id
    }

    mutating func userString(_ text: String, meta: Bool = false, extra: [(String, JSON)] = []) {
        let id = newUUID()
        var fields: [(String, JSON)] = [("parentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)),
                                        ("promptId", .string(promptId)), ("type", .string("user")),
                                        ("message", .object([("role", .string("user")), ("content", .string(text))]))]
        if meta { fields.append(("isMeta", .bool(true))) }
        fields.append(contentsOf: [("uuid", .string(id)), ("timestamp", .string(timestamp(advance: 30)))])
        fields.append(contentsOf: extra)
        fields.append(contentsOf: tail())
        emit(fields)
        parent = id
    }

    mutating func extras() {
        if random.chance(0.12) {
            userString("<task-notification>\n<task-id>b" + token(8).lowercased() + "</task-id>\n<status>completed</status>\n<summary>Background command \"build\" completed (exit code 0)</summary>\n</task-notification>",
                       extra: [("origin", .object([("kind", .string("task-notification"))])), ("promptSource", .string("system"))])
        }
        if random.chance(0.05) {
            promptId = newUUID()
            userString("<local-command-caveat>Caveat: The messages below were generated by the user while running local commands.</local-command-caveat>", meta: true)
            userString("<command-name>/model</command-name>\n            <command-message>model</command-message>\n            <command-args>opus</command-args>")
            userString("<local-command-stdout>Set model to Opus 5.5</local-command-stdout>")
        }
        if random.chance(0.1) {
            system("away_summary", [("content", .raw(prose(random.int(200...600))))], advance: random.int(60_000...600_000))
        }
        if !compacted && turn > 40 && random.chance(0.05) {
            compacted = true
            let id = newUUID()
            emit([("parentUuid", .null), ("logicalParentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)),
                  ("type", .string("system")), ("subtype", .string("compact_boundary")), ("content", .string("Conversation compacted")),
                  ("level", .string("info")), ("compactMetadata", .object([("trigger", .string("auto")), ("preTokens", .int(180_000))])),
                  ("uuid", .string(id)), ("timestamp", .string(timestamp(advance: 30_000)))] + tail(stale: false, slug: true))
            parent = id
            userString("This session is being continued from a previous conversation that ran out of context.\n\nSummary:\n" + prose(3_000).replacingOccurrences(of: "\\n", with: "\n"),
                       extra: [("isVisibleInTranscriptOnly", .bool(true)), ("isCompactSummary", .bool(true))])
        }
    }

    mutating func turnBlock() {
        turn += 1
        let text = prose(random.chance(0.1) ? random.int(4_000...20_000) : random.int(80...600))
        prompt(text: text, images: random.chance(0.05) ? random.int(1...2) : 0)
        for _ in 0..<random.int(2...5) { attachment() }
        metadataTail(prompt: "Prompt do turno \(turn)")
        let rounds = random.int(2...16)
        for round in 0..<rounds {
            startMessage()
            if random.chance(0.7) { thinking() }
            if random.chance(0.25) {
                assistant(block: .object([("type", .string("text")), ("text", .raw(prose(random.int(100...900))))]), stopReason: "tool_use")
            }
            toolRound()
            if round % 2 == 0 { attachment() }
        }
        startMessage()
        thinking()
        if random.chance(0.03) {
            let interrupted = messageId
            assistant(block: .object([("type", .string("text")), ("text", .raw(prose(random.int(200...800))))]), stopReason: nil)
            let id = newUUID()
            emit([("parentUuid", parent.map { .string($0) } ?? .null), ("isSidechain", .bool(false)), ("promptId", .string(promptId)),
                  ("type", .string("user")),
                  ("message", .object([("role", .string("user")), ("content", .array([.object([("type", .string("text")), ("text", .string("[Request interrupted by user]"))])]))])),
                  ("uuid", .string(id)), ("timestamp", .string(timestamp(advance: 500))), ("interruptedMessageId", .string(interrupted))] + tail())
            parent = id
        } else {
            assistant(block: .object([("type", .string("text")), ("text", .raw(prose(random.int(400...4_000))))]), stopReason: "end_turn")
            system("turn_duration", [("durationMs", .int(random.int(3_000...900_000))), ("messageCount", .int(rounds * 4 + 6)),
                                     ("pendingBackgroundAgentCount", .int(0))])
        }
        metadataTail(prompt: "Prompt do turno \(turn)")
        extras()
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let defaultOutput = repositoryRoot.appendingPathComponent("MochaKit/Fixtures/transcripts/generated/big-50mb.jsonl")
let output = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : defaultOutput
guard let megabytes = Int(arguments.count > 2 ? arguments[2] : "50"), megabytes > 0 else {
    fail("uso: swift scripts/gen-big-transcript.swift [saída] [MB]")
}
let targetBytes = megabytes * 1_000_000

do {
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
} catch {
    fail("não consegui criar \(output.deletingLastPathComponent().path): \(error)")
}
guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
    fail("não consegui criar \(output.path)")
}
guard let handle = FileHandle(forWritingAtPath: output.path) else {
    fail("não consegui abrir \(output.path)")
}

var generator = Generator()
generator.emit([("type", .string("mode")), ("mode", .string("normal")), ("sessionId", .string(generator.sessionId))])
generator.emit([("type", .string("permission-mode")), ("permissionMode", .string("auto")), ("sessionId", .string(generator.sessionId))])
var written = 0
while written < targetBytes {
    generator.turnBlock()
    let data = Data(generator.buffer.utf8)
    generator.buffer = ""
    do {
        try handle.write(contentsOf: data)
    } catch {
        fail("falha ao escrever: \(error)")
    }
    written += data.count
}
do {
    try handle.close()
} catch {
    fail("falha ao fechar: \(error)")
}
print("\(output.path): \(written) bytes, \(generator.lineCount) linhas, \(generator.turn) turnos, sessionId \(generator.sessionId)")
