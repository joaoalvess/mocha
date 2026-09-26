import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct ToolGroupingTests {
    private static let start = Date(timeIntervalSince1970: 1_790_337_600)

    private static func item(_ id: String, _ kind: ChatItemKind) -> ChatItem {
        ChatItem(id: id, at: start, kind: kind)
    }

    private static func tool(_ id: String, _ name: String, _ summary: String = "x", status: ToolStatus = .succeeded, input: String = "{}") -> ChatItem {
        item(id, .toolCall(ToolCall(toolUseId: "toolu_" + id, name: name, summary: summary, inputJSON: input, status: status)))
    }

    private static func groups(_ entries: [ChatEntry]) -> [ToolGroup] {
        entries.compactMap { if case .tools(let group) = $0 { group } else { nil } }
    }

    @Test func groupsConsecutiveCallsOfTheSameTool() {
        let items = [
            Self.item("p", .userPrompt(text: "oi", imageCount: 0)),
            Self.tool("r1", "Read", "Auth/AuthService.swift"),
            Self.tool("r2", "Read", "Auth/AuthService.swift"),
            Self.tool("e1", "Edit", "DemoApp.entitlements"),
            Self.tool("b1", "Bash", "xcodebuild", status: .failed),
            Self.tool("b2", "Bash", "xcodebuild", status: .failed),
            Self.tool("b3", "Bash", "xcodebuild", status: .failed),
            Self.item("t", .assistantText(markdown: "O build falhou.")),
        ]
        let entries = ToolGrouping.entries(from: items)
        #expect(entries.map(\.id) == ["p", "r1", "e1", "b1", "t"])
        let groups = Self.groups(entries)
        #expect(groups.map(\.count) == [2, 1, 3])
        #expect(groups.map(\.displayName) == ["Read", "Edit", "Shell"])
        #expect(groups.map(\.icon) == [.document, .pencil, .shell])
        #expect(groups.map(\.status) == [.succeeded, .succeeded, .failed])
        #expect(groups[0].itemIds == ["r1", "r2"])
        #expect(groups[2].summary == "xcodebuild")
    }

    @Test func anyFailedCallMarksTheGroupFailed() {
        let entries = ToolGrouping.entries(from: [
            Self.tool("a", "Bash", status: .succeeded),
            Self.tool("b", "Bash", status: .failed),
            Self.tool("c", "Bash", status: .running),
        ])
        #expect(Self.groups(entries).map(\.status) == [.failed])
    }

    @Test func runningWinsOverSucceededWhenNothingFailed() {
        let entries = ToolGrouping.entries(from: [
            Self.tool("a", "Bash", status: .succeeded),
            Self.tool("b", "Bash", status: .running),
        ])
        #expect(Self.groups(entries).map(\.status) == [.running])
    }

    @Test func summaryComesFromTheFirstCall() {
        let entries = ToolGrouping.entries(from: [
            Self.tool("a", "Read", "store.go"),
            Self.tool("b", "Read", "handler.go"),
        ])
        #expect(Self.groups(entries).map(\.summary) == ["store.go"])
    }

    @Test func anythingBetweenCallsBreaksTheGroup() {
        let entries = ToolGrouping.entries(from: [
            Self.tool("a", "Bash"),
            Self.item("k", .thinking(text: nil)),
            Self.tool("b", "Bash"),
            Self.item("t", .assistantText(markdown: "ok")),
            Self.tool("c", "Bash"),
        ])
        #expect(Self.groups(entries).map(\.count) == [1, 1, 1])
        #expect(entries.map(\.id) == ["a", "k", "b", "t", "c"])
    }

    @Test func differentToolsStaySeparate() {
        let entries = ToolGrouping.entries(from: [
            Self.tool("a", "Bash"),
            Self.tool("b", "BashOutput"),
            Self.tool("c", "Bash"),
        ])
        #expect(Self.groups(entries).map(\.toolName) == ["Bash", "BashOutput", "Bash"])
    }

    @Test func consecutiveThinkingBecomesOneLine() {
        let entries = ToolGrouping.entries(from: [
            Self.item("k1", .thinking(text: nil)),
            Self.item("k2", .thinking(text: "  Preciso ler o AuthService.  ")),
            Self.item("k3", .thinking(text: "")),
            Self.item("k4", .thinking(text: "E o entitlement.")),
            Self.tool("a", "Read"),
            Self.item("k5", .thinking(text: nil)),
        ])
        #expect(entries.map(\.id) == ["k1", "a", "k5"])
        guard case .thinking(let first) = entries[0], case .thinking(let last) = entries[2] else {
            Issue.record("esperava duas linhas de thinking")
            return
        }
        #expect(first.itemIds == ["k1", "k2", "k3", "k4"])
        #expect(first.texts == ["Preciso ler o AuthService.", "E o entitlement."])
        #expect(first.text == "Preciso ler o AuthService.\n\nE o entitlement.")
        #expect(last.text == nil)
    }

    @Test func unsupportedItemsAreDroppedWithoutBreakingGroups() {
        let entries = ToolGrouping.entries(from: [
            Self.tool("a", "Bash"),
            Self.item("u", .unsupported(type: "futureThing")),
            Self.tool("b", "Bash"),
        ])
        #expect(entries.map(\.id) == ["a"])
        #expect(Self.groups(entries).first?.itemIds == ["a", "b"])
    }

    @Test func otherItemsPassThroughInOrder() {
        let items = [
            Self.item("s", .slashCommand(name: "/clear", args: "", output: nil)),
            Self.item("p", .userPrompt(text: "oi", imageCount: 0)),
            Self.item("f", .turnFooter(durationMs: 45_000)),
            Self.item("r", .recap(text: "Resumo")),
            Self.item("n", .notice(text: "Conversa compactada")),
        ]
        #expect(ToolGrouping.entries(from: items) == items.map(ChatEntry.item))
    }

    @Test func shellInputIsTheCommand() {
        let call = ToolCall(
            toolUseId: "t",
            name: "Bash",
            summary: "cat /private/tmp/…/b7k2q.output",
            inputJSON: #"{"command":"cat /private/tmp/claude-501/demo-app/tasks/b7k2q.output"}"#,
            status: .succeeded
        )
        #expect(ToolGrouping.input(for: call) == ToolInput(text: "cat /private/tmp/claude-501/demo-app/tasks/b7k2q.output", isShellCommand: true))
    }

    @Test func otherToolsShowTheirMainArgument() {
        let read = ToolCall(toolUseId: "r", name: "Read", summary: "store.go", inputJSON: #"{"file_path":"/repo/store.go"}"#, status: .succeeded)
        let grep = ToolCall(toolUseId: "g", name: "Grep", summary: "OFFSET", inputJSON: #"{"path":"internal","pattern":"OFFSET"}"#, status: .succeeded)
        #expect(ToolGrouping.input(for: read) == ToolInput(text: "/repo/store.go", isShellCommand: false))
        #expect(ToolGrouping.input(for: grep) == ToolInput(text: "OFFSET", isShellCommand: false))
    }

    @Test func truncatedInputFallsBackToTheSummary() {
        let call = ToolCall(toolUseId: "b", name: "Bash", summary: "swift test", inputJSON: #"{"command":"swift te"#, status: .running)
        #expect(ToolGrouping.input(for: call) == ToolInput(text: "swift test", isShellCommand: false))
    }
}
