import Foundation
import MochaProtocol
import MochaTestSupport
import Testing
@testable import MochaTranscript

enum HomeLines {
    static func stamp(_ time: String) -> String {
        "2026-09-26T\(time).000Z"
    }

    static func date(_ time: String) -> Date? {
        ProtocolDate.date(from: stamp(time))
    }

    static func user(_ content: Any, at time: String, uuid: String = UUID().uuidString, extra: [String: Any] = [:]) -> String {
        TranscriptLines.user(content, uuid: uuid, extra: ["timestamp": stamp(time)].merging(extra) { $1 })
    }

    static func assistant(
        _ blocks: [[String: Any]],
        at time: String,
        usage: [Int]? = [10, 100, 1_000],
        model: String = "claude-opus-5-5",
        uuid: String = UUID().uuidString,
        extra: [String: Any] = [:]
    ) -> String {
        var message: [String: Any] = ["model": model, "id": "msg_\(uuid)", "role": "assistant", "content": blocks]
        if let usage {
            message["usage"] = [
                "input_tokens": usage[0],
                "cache_creation_input_tokens": usage[1],
                "cache_read_input_tokens": usage[2],
                "output_tokens": 77,
            ]
        }
        var object: [String: Any] = [
            "type": "assistant",
            "uuid": uuid,
            "timestamp": stamp(time),
            "message": message,
            "cwd": "/Users/dev/projects/demo-app",
            "gitBranch": "main",
            "version": "2.1.283",
        ]
        object.merge(extra) { $1 }
        return TranscriptLines.json(object)
    }

    static func text(_ text: String, at time: String, usage: [Int]? = [10, 100, 1_000]) -> String {
        assistant([["type": "text", "text": text]], at: time, usage: usage)
    }

    static func toolUse(_ name: String, id: String, input: [String: Any], at time: String, usage: [Int]? = [10, 100, 1_000]) -> String {
        assistant([["type": "tool_use", "id": id, "name": name, "input": input]], at: time, usage: usage)
    }

    static func toolResult(_ id: String, isError: Bool = false, at time: String) -> String {
        user([["type": "tool_result", "tool_use_id": id, "content": "saída", "is_error": isError]], at: time)
    }

    static func turnDuration(at time: String) -> String {
        TranscriptLines.system("turn_duration", extra: ["durationMs": 1_000, "timestamp": stamp(time)])
    }

    static func queued(_ prompt: Any, at time: String) -> String {
        TranscriptLines.json([
            "type": "attachment",
            "uuid": UUID().uuidString,
            "timestamp": stamp(time),
            "attachment": ["type": "queued_command", "commandMode": "prompt", "prompt": prompt],
        ])
    }

    static func metadata() -> String {
        TranscriptLines.json(["type": "permission-mode", "permissionMode": "default"])
    }
}

struct HomeMetaReadings {
    let full: TranscriptHeader
    let scanned: TranscriptHeader
    let followed: TranscriptHeader
    let incremental: TranscriptHeader

    static func of(_ lines: [String]) throws -> HomeMetaReadings {
        let bytes = Array((lines.joined(separator: "\n") + "\n").utf8)
        let transcript = try TemporaryTranscript(contents: bytes)
        let growing = try TemporaryTranscript()
        let incremental = try TranscriptFollower(path: growing.path, start: .beginningOfFile)
        for line in lines {
            try growing.append(Array((line + "\n").utf8))
            _ = try incremental.readAppendedLines()
        }
        return HomeMetaReadings(
            full: TranscriptDocument(bytes: bytes).header,
            scanned: try TranscriptHeaderScanner.header(ofFileAt: transcript.path),
            followed: try TranscriptFollower(path: transcript.path, start: .afterExistingLines).header,
            incremental: incremental.header
        )
    }

    func expectConsistent(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(scanned == full, "varredura do fim", sourceLocation: sourceLocation)
        #expect(followed == full, "acompanhamento a partir do fim", sourceLocation: sourceLocation)
        #expect(incremental == full, "acompanhamento linha a linha", sourceLocation: sourceLocation)
    }
}

@Suite
struct TranscriptHomeMetaTests {
    private typealias H = HomeLines

    @Test func homeFieldsFollowTheSpecRules() throws {
        let readings = try HomeMetaReadings.of([
            H.metadata(),
            H.user("Primeiro **pedido**", at: "10:00:00"),
            H.text("Resposta com `código`", at: "10:00:01", usage: [1, 2, 3]),
            H.toolUse("Bash", id: "t1", input: ["command": "npm test\nlinha 2"], at: "10:00:02", usage: [4, 5, 6]),
            H.toolUse("Read", id: "t2", input: ["file_path": "/Users/dev/projects/demo-app/src/app.ts"], at: "10:00:03", usage: [7, 8, 9]),
            H.toolResult("t2", at: "10:00:04"),
            H.assistant([["type": "text", "text": "API Error: 529"]], at: "10:00:05", usage: [900, 900, 900], model: "<synthetic>", extra: ["isApiErrorMessage": true]),
            H.assistant([["type": "text", "text": "lateral"]], at: "10:00:05", usage: [500, 500, 500], extra: ["isSidechain": true]),
            H.queued("fila **enquanto** trabalha", at: "10:00:06"),
            H.turnDuration(at: "10:00:07"),
        ])
        readings.expectConsistent()
        let header = readings.full
        #expect(header.preview == MessagePreview(author: .user, text: "fila enquanto trabalha"))
        #expect(header.activity == ToolActivity(toolName: "Bash", summary: "npm test", status: .running))
        #expect(header.contextTokens == 24)
        #expect(header.sessionStartedAt == H.date("10:00:00"))
        #expect(header.turnStartedAt == H.date("10:00:00"))
        #expect(header.turnEndedAt == H.date("10:00:07"))
    }

    @Test func activityPrefersTheLastRunningToolCall() throws {
        let readings = try HomeMetaReadings.of([
            H.user("paralelo", at: "10:00:00"),
            H.toolUse("Bash", id: "a", input: ["command": "sleep 60"], at: "10:00:01"),
            H.toolUse("Grep", id: "b", input: ["pattern": "TODO"], at: "10:00:02"),
            H.toolUse("Read", id: "c", input: ["file_path": "README.md"], at: "10:00:03"),
            H.toolResult("c", at: "10:00:04"),
            H.toolResult("b", isError: true, at: "10:00:05"),
        ])
        readings.expectConsistent()
        #expect(readings.full.activity == ToolActivity(toolName: "Bash", summary: "sleep 60", status: .running))
    }

    @Test func activityFallsBackToTheLastToolCallWhenNoneIsRunning() throws {
        let readings = try HomeMetaReadings.of([
            H.user("sequência", at: "10:00:00"),
            H.toolUse("Bash", id: "a", input: ["command": "ls"], at: "10:00:01"),
            H.toolResult("a", at: "10:00:02"),
            H.toolUse("Edit", id: "b", input: ["file_path": "/Users/dev/projects/demo-app/a.ts"], at: "10:00:03"),
            H.toolResult("b", isError: true, at: "10:00:04"),
            H.text("Pronto.", at: "10:00:05"),
        ])
        readings.expectConsistent()
        #expect(readings.full.activity == ToolActivity(toolName: "Edit", summary: "a.ts", status: .failed))
        #expect(readings.full.preview == MessagePreview(author: .assistant, text: "Pronto."))
    }

    @Test func duplicateToolUseIdsResolveOnlyTheLatestCall() throws {
        let readings = try HomeMetaReadings.of([
            H.toolUse("Bash", id: "dup", input: ["command": "primeiro"], at: "10:00:01"),
            H.toolUse("Bash", id: "dup", input: ["command": "segundo"], at: "10:00:02"),
            H.toolResult("dup", at: "10:00:03"),
            H.toolResult("dup", isError: true, at: "10:00:04"),
        ])
        readings.expectConsistent()
        #expect(readings.full.activity == ToolActivity(toolName: "Bash", summary: "primeiro", status: .running))
    }

    @Test func imageOnlyPromptPreviewsAsImagem() throws {
        let image: [String: Any] = ["type": "image", "source": ["type": "base64", "data": "AAAA"]]
        let onlyImage = try HomeMetaReadings.of([H.user([image], at: "10:00:00")])
        onlyImage.expectConsistent()
        #expect(onlyImage.full.preview == MessagePreview(author: .user, text: "[imagem]"))
        let withText = try HomeMetaReadings.of([H.user([["type": "text", "text": "olha **isso**"], image], at: "10:00:00")])
        withText.expectConsistent()
        #expect(withText.full.preview == MessagePreview(author: .user, text: "olha isso"))
    }

    @Test func sessionWithoutMessagesHasNoPreviewNorActivity() throws {
        let readings = try HomeMetaReadings.of([
            H.user("<local-command-caveat>Caveat</local-command-caveat>", at: "10:00:00", extra: ["isMeta": true]),
            H.user("<command-name>/clear</command-name>\n<command-message>clear</command-message>\n<command-args></command-args>", at: "10:00:01"),
            H.metadata(),
        ])
        readings.expectConsistent()
        #expect(readings.full.preview == nil)
        #expect(readings.full.activity == nil)
        #expect(readings.full.turnStartedAt == nil)
        #expect(readings.full.turnEndedAt == nil)
        #expect(readings.full.contextTokens == nil)
        #expect(readings.full.sessionStartedAt == H.date("10:00:00"))
    }

    @Test func interruptedTurnKeepsTheOlderTurnEnd() throws {
        let readings = try HomeMetaReadings.of([
            H.user("primeiro", at: "10:00:00"),
            H.text("feito", at: "10:00:01"),
            H.turnDuration(at: "10:00:02"),
            H.user("segundo", at: "10:05:00"),
            H.user([["type": "text", "text": "[Request interrupted by user]"]], at: "10:05:03"),
        ])
        readings.expectConsistent()
        #expect(readings.full.turnStartedAt == H.date("10:05:00"))
        #expect(readings.full.turnEndedAt == H.date("10:00:02"))
        #expect(readings.full.preview == MessagePreview(author: .user, text: "segundo"))
    }

    @Test func assistantLineWithoutUsageKeepsTheLastKnownContext() throws {
        let readings = try HomeMetaReadings.of([
            H.text("com uso", at: "10:00:00", usage: [1, 10, 100]),
            H.text("sem uso", at: "10:00:01", usage: nil),
        ])
        readings.expectConsistent()
        #expect(readings.full.contextTokens == 111)
    }

    @Test func queuedCommandFeedsThePreviewButDoesNotStartATurn() throws {
        let bytes = try TranscriptFixtures.bytes("images-and-queued")
        let bashResult = "\"tool_use_id\":\"toolu_01wjBUFevWSaCvJkyiujnfGN\""
        let cut = try #require(try FixtureLines.offsets(of: "images-and-queued", containing: bashResult).first)
        let prefix = Array(bytes[..<Int(cut)])
        let lines = String(decoding: prefix, as: UTF8.self).split(separator: "\n").map(String.init)
        let readings = try HomeMetaReadings.of(lines)
        readings.expectConsistent()
        #expect(readings.full.preview == MessagePreview(author: .user, text: "aproveita e roda o prettier também"))
        #expect(readings.full.turnStartedAt == ProtocolDate.date(from: "2026-09-25T15:00:35.819Z"))
        #expect(readings.full.turnEndedAt == ProtocolDate.date(from: "2026-09-25T15:00:05.818Z"))
        #expect(readings.full.activity?.toolName == "Bash")
        #expect(readings.full.activity?.status == .running)
    }

    @Test func runningCallOlderThanTheSeedWindowSurvivesFollowing() throws {
        var lines = [
            H.user("longo", at: "10:00:00"),
            H.toolUse("AskUserQuestion", id: "pergunta", input: ["questions": [["question": "Qual banco?"]]], at: "10:00:01"),
        ]
        for index in 0..<150 {
            lines.append(H.toolUse("Bash", id: "t\(index)", input: ["command": "echo \(index)"], at: "10:01:00"))
            lines.append(H.toolResult("t\(index)", at: "10:01:01"))
        }
        let readings = try HomeMetaReadings.of(lines)
        readings.expectConsistent()
        #expect(readings.full.activity == ToolActivity(toolName: "AskUserQuestion", summary: "Qual banco?", status: .running))
    }

    @Test func appendedToolUseAndResultChangeTheFollowedActivity() throws {
        let transcript = try TemporaryTranscript(contents: Array((H.user("oi", at: "10:00:00") + "\n").utf8))
        let follower = try TranscriptFollower(path: transcript.path, start: .afterExistingLines)
        #expect(follower.header.activity == nil)
        try transcript.append(Array((H.toolUse("Bash", id: "x", input: ["command": "make"], at: "10:00:01") + "\n").utf8))
        _ = try follower.readAppendedLines()
        #expect(follower.header.activity == ToolActivity(toolName: "Bash", summary: "make", status: .running))
        try transcript.append(Array((H.toolResult("x", isError: true, at: "10:00:02") + "\n").utf8))
        _ = try follower.readAppendedLines()
        #expect(follower.header.activity == ToolActivity(toolName: "Bash", summary: "make", status: .failed))
    }

    @Test func scanStopsAfterEightMegabytesButStillReadsTheFirstLine() throws {
        var lines = [
            TranscriptLines.json(["type": "ai-title", "aiTitle": "Antigo"]),
            H.user("pedido antigo", at: "09:00:00"),
            H.toolUse("Bash", id: "velho", input: ["command": "sleep 1"], at: "09:00:01"),
        ]
        let filler = String(repeating: "x", count: 200_000)
        for index in 0..<45 {
            lines.append(TranscriptLines.json(["type": "mode", "mode": "normal", "n": index, "pad": filler]))
        }
        lines.append(H.text("recente", at: "11:00:00"))
        let bytes = Array((lines.joined(separator: "\n") + "\n").utf8)
        #expect(UInt64(bytes.count) > TranscriptHeaderScanner.scanLimit)
        let transcript = try TemporaryTranscript(contents: bytes)
        let scanned = try TranscriptHeaderScanner.header(ofFileAt: transcript.path)
        #expect(scanned.title == nil)
        #expect(scanned.turnStartedAt == nil)
        #expect(scanned.activity == nil)
        #expect(scanned.preview == MessagePreview(author: .assistant, text: "recente"))
        #expect(scanned.sessionStartedAt == H.date("09:00:00"))
        let full = TranscriptDocument(bytes: bytes).header
        #expect(full.title == "Antigo")
        #expect(full.activity == ToolActivity(toolName: "Bash", summary: "sleep 1", status: .running))
    }

    @Test func scanOfAFileExactlyAsLargeAsTheLimitReadsTheFirstLine() throws {
        let lines = [
            TranscriptLines.json(["type": "ai-title", "aiTitle": "No limite"]),
            H.user("pedido", at: "09:00:00"),
            H.text("resposta", at: "09:00:01"),
        ]
        let bytes = Array((lines.joined(separator: "\n") + "\n").utf8)
        let transcript = try TemporaryTranscript(contents: bytes)
        let scanned = try TranscriptHeaderScanner.scan(fileAt: transcript.path, limit: UInt64(bytes.count)).header
        #expect(scanned.title == "No limite")
        #expect(scanned.turnStartedAt == H.date("09:00:00"))
        #expect(scanned.preview == MessagePreview(author: .assistant, text: "resposta"))
    }

    @Test(arguments: TranscriptFixtures.names)
    func fixtureHomeFieldsMatchTheRawLinesAndTheItems(_ name: String) throws {
        let snapshot = try TranscriptFixtures.expectedSnapshot(name)
        let raw = RawFixtureLines(name)
        #expect(snapshot.meta.sessionStartedAt == raw.firstTimestamp)
        #expect(snapshot.meta.turnEndedAt == raw.lastTurnDurationTimestamp)
        #expect(snapshot.meta.contextTokens == raw.lastAssistantContextTokens)
        #expect(snapshot.meta.contextTokens == 19_212)

        let lastMessage = snapshot.items.last { item in
            switch item.kind {
            case .userPrompt, .assistantText: true
            default: false
            }
        }
        #expect(snapshot.meta.preview == lastMessage.flatMap(MessagePreview.init(transcriptItem:)))
        let calls = snapshot.items.compactMap { item -> ToolCall? in
            if case .toolCall(let call) = item.kind { return call }
            return nil
        }
        let expectedCall = calls.last { $0.status == .running } ?? calls.last
        #expect(snapshot.meta.activity == expectedCall.map(ToolActivity.init(call:)))
    }

    @Test func fixtureTurnStartsMatchTheHandCheckedValues() throws {
        let expected: [String: String] = [
            "basic-turn": "2026-09-25T15:01:05.832Z",
            "tool-calls": "2026-09-25T15:00:04.001Z",
            "images-and-queued": "2026-09-25T15:00:54.253Z",
            "subagents": "2026-09-25T15:00:04.001Z",
            "malformed": "2026-09-25T15:00:20.538Z",
        ]
        for (name, stamp) in expected {
            #expect(try TranscriptFixtures.expectedSnapshot(name).meta.turnStartedAt == ProtocolDate.date(from: stamp), "\(name)")
        }
        let malformed = try TranscriptFixtures.expectedSnapshot("malformed").meta
        #expect(try #require(malformed.turnEndedAt) < (try #require(malformed.turnStartedAt)))
    }

    @Test(arguments: TranscriptFixtures.names)
    func lineOutlinesAgreeWithTheParser(_ name: String) throws {
        let bytes = try TranscriptFixtures.bytes(name)
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            let line = Array(bytes[start..<index])
            start = index + 1
            line.withUnsafeBytes { buffer in
                let parsed = TranscriptLineParser.parse(buffer, offset: 0)
                let outline = LineOutline.of(buffer)
                let parsedResults = parsed.effects.compactMap { effect -> LineOutline.ToolResult? in
                    if case .toolResult(let outcome) = effect { return LineOutline.ToolResult(toolUseId: outcome.toolUseId, isError: outcome.isError) }
                    return nil
                }
                let parsedToolUses = parsed.effects.compactMap { effect -> String? in
                    guard case .item(let item) = effect else { return nil }
                    switch item.kind {
                    case .toolCall(let call): return call.toolUseId
                    case .subagent(let call): return call.toolUseId
                    case .workflow(let call): return call.toolUseId
                    default: return nil
                    }
                }
                #expect((outline?.toolResults ?? []) == parsedResults)
                #expect((outline?.toolUseIds ?? []) == parsedToolUses)
                #expect(outline?.date == parsed.date)
                #expect(outline?.version == (outline == nil ? nil : parsed.version))
            }
        }
    }

    @Test func lineOutlineRejectsWhatTheParserDrops() {
        let samples = [
            "{\"type\":\"user\"",
            "não é json",
            "{\"sem\":\"type\"}",
            "[1,2]",
            "{\"type\":\"user\",\"message\":{\"content\":\"a\\x\"}}",
            "{\"type\":\"user\",\"message\":{\"content\":\"\u{01}\"}}",
            "{\"type\":1}",
            "{\"type\":\"user\"} lixo",
        ]
        for sample in samples {
            Array(sample.utf8).withUnsafeBytes { buffer in
                #expect(LineOutline.of(buffer) == nil, "\(sample)")
            }
        }
        let valid = "{\"type\":\"user\",\"isMeta\":false,\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t\\u0031\",\"is_error\":true,\"content\":[{\"type\":\"text\",\"text\":\"a\\\"b\\n\"}]},2,null],\"x\":[1.5e3,-0,true]},\"version\":\"2.1.283\"}"
        Array(valid.utf8).withUnsafeBytes { buffer in
            let outline = LineOutline.of(buffer)
            #expect(outline?.toolResults == [LineOutline.ToolResult(toolUseId: "t1", isError: true)])
            #expect(outline?.version == "2.1.283")
        }
    }
}

private struct RawFixtureLines {
    let objects: [[String: Any]]

    init(_ name: String) {
        let bytes = (try? TranscriptFixtures.bytes(name)) ?? []
        objects = bytes.split(separator: 0x0A).compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] is String,
                  object["isSidechain"] as? Bool != true else { return nil }
            return object
        }
    }

    private func date(_ object: [String: Any]) -> Date? {
        (object["timestamp"] as? String).flatMap(ProtocolDate.date(from:))
    }

    var firstTimestamp: Date? {
        objects.lazy.compactMap(date).first
    }

    var lastTurnDurationTimestamp: Date? {
        objects.last { $0["type"] as? String == "system" && $0["subtype"] as? String == "turn_duration" }.flatMap(date)
    }

    var lastAssistantContextTokens: Int? {
        let assistant = objects.last { object in
            guard object["type"] as? String == "assistant",
                  object["isApiErrorMessage"] as? Bool != true,
                  let message = object["message"] as? [String: Any],
                  message["model"] as? String != "<synthetic>" else { return false }
            return message["usage"] is [String: Any]
        }
        guard let usage = (assistant?["message"] as? [String: Any])?["usage"] as? [String: Any] else { return nil }
        return ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage[$0] as? Int }.reduce(0, +)
    }
}
