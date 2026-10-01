import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.tags(.integration), .enabled(if: CodexLab.isEnabled), .timeLimit(.minutes(4)))
struct CodexThreadCycleIntegrationTests {
    @Test func theTUIOpensAThreadInTheLabThatTheDaemonCanBind() async throws {
        let lab = try #require(CodexLab.current)
        let cycle = try await CodexLabCycle.shared.value
        let started = try #require(cycle.events("thread/started").first { $0.params["thread"]?["id"]?.stringValue == cycle.threadId })
        let thread = started.params["thread"] ?? .null
        #expect(thread["cwd"]?.stringValue.map(CodexLab.standardized) == lab.workDirectory, "thread/started real: \(thread.compactSerialized())")
        #expect(thread["ephemeral"]?.boolValue == false && thread["parentThreadId"] == .null, "thread/started real: \(thread.compactSerialized())")
        let loaded = cycle.responses["thread/loaded/list"]?["data"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(loaded.contains(cycle.threadId), "thread/loaded/list real: \(loaded)")
    }

    @Test func aPromptSentLikeTheDaemonRunsInTheTUI() async throws {
        let cycle = try await CodexLabCycle.shared.value
        let completed = cycle.events("turn/completed").first
        #expect(completed?.params["turn"]?["status"]?.stringValue == "completed", "turn/completed real: \(completed?.params.compactSerialized() ?? "-")")
        let messages = cycle.events("item/completed").compactMap(\.params["item"]).filter { $0["type"]?.stringValue == "agentMessage" }
        #expect(messages.contains { $0["text"]?.stringValue?.contains(CodexLabCycle.answer) == true }, "agentMessage real: \(messages.map { $0.compactSerialized() })")
        let screen = cycle.screens["turn"] ?? ""
        #expect(CodexLabCycle.showsAnswer(screen), "tela real do TUI:\n\(screen)")
        let usage = cycle.events("thread/tokenUsage/updated").last?.params["tokenUsage"]
        #expect(usage?["last"]?["totalTokens"] != nil && usage?["modelContextWindow"] != nil, "thread/tokenUsage/updated real: \(usage?.compactSerialized() ?? "-")")
    }

    @Test func experimentalSettingsReachTheTUI() async throws {
        let cycle = try await CodexLabCycle.shared.value
        let failures = cycle.failures.filter { $0.key.hasPrefix("thread/settings") || $0.key == "model/list" }
        #expect(failures.isEmpty, "controles reais: \(failures)")
        let updates = cycle.events("thread/settings/updated").compactMap(\.params["threadSettings"])
        let modes = updates.compactMap { $0["collaborationMode"]?["mode"]?.stringValue }
        #expect(modes.contains("plan") && modes.last == "default", "thread/settings/updated real: \(updates.map { $0.compactSerialized() })")
        #expect(updates.last?["effort"]?.stringValue != nil && updates.last?["model"]?.stringValue != nil, "thread/settings/updated real: \(updates.last?.compactSerialized() ?? "-")")
        let screen = cycle.screens["plan"] ?? ""
        #expect(CodexLabCycle.showsPlanMode(screen), "tela real do TUI em Plano:\n\(screen)")
    }

    @Test func historyComesFromTheItemsAndTurnsLists() async throws {
        let cycle = try await CodexLabCycle.shared.value
        let failures = cycle.failures.filter { ["thread/read", "thread/turns/list", "thread/items/list"].contains($0.key) }
        #expect(failures.isEmpty, "histórico real: \(failures)")
        let entries = cycle.responses["thread/items/list"]?["data"]?.arrayValue ?? []
        let types = entries.compactMap { $0["item"]?["type"]?.stringValue }
        #expect(types.contains("userMessage") && types.contains("agentMessage"), "thread/items/list real: \(entries.map { $0.compactSerialized() })")
        #expect(entries.allSatisfy { $0["startedAtMs"]?.numberValue != nil && $0["item"]?["id"]?.stringValue != nil }, "thread/items/list real: \(entries.map { $0.compactSerialized() })")
        let prompt = entries.compactMap { $0["item"] }.first { $0["type"]?.stringValue == "userMessage" }?["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }
        #expect(prompt == [CodexLabCycle.prompt], "userMessage real: \(prompt ?? [])")
        let turnItems = cycle.responses["thread/turns/list"]?["data"]?.arrayValue?.first?["items"]?.arrayValue ?? []
        #expect(turnItems.contains { $0["type"]?.stringValue == "agentMessage" }, "thread/turns/list real: \(turnItems.map { $0.compactSerialized() })")
        let thread = cycle.responses["thread/read"]?["thread"]
        #expect(thread?["id"]?.stringValue == cycle.threadId && thread?["createdAt"]?.numberValue != nil, "thread/read real: \(thread?.compactSerialized() ?? "-")")
    }
}
