import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct ChatImageVisibilityTests {
    private static let at = Date(timeIntervalSince1970: 1_790_337_600)
    private static let upload = "/Users/joao/Library/Application Support/Mocha/uploads/a.jpg"
    private static let print = "/Users/joao/Desktop/print.png"

    private static func prompt(_ id: String, _ paths: [String] = []) -> ChatItem {
        ChatItem(id: id, at: at, kind: .userPrompt(text: "olha", imageCount: paths.count), imagePaths: paths)
    }

    private static func text(_ id: String, _ paths: [String]) -> ChatItem {
        ChatItem(id: id, at: at, kind: .assistantText(markdown: "veja"), imagePaths: paths)
    }

    private static func read(_ id: String, _ paths: [String]) -> ChatItem {
        let call = ToolCall(toolUseId: "toolu_" + id, name: "Read", summary: "print.png", inputJSON: "{}", status: .succeeded)
        return ChatItem(id: id, at: at, kind: .toolCall(call), imagePaths: paths)
    }

    @Test func eachPathAppearsOnlyTheFirstTimeInATurn() {
        let items = [
            Self.prompt("p1", [Self.upload]),
            Self.text("t1", [Self.upload, Self.print]),
            Self.read("r1", [Self.print]),
            Self.text("t2", [Self.print]),
        ]
        let visible = ChatImageVisibility.visiblePaths(in: items)
        #expect(visible == ["p1": [Self.upload], "t1": [Self.print]])
    }

    @Test func readThenMentionShowsUnderTheReadOnly() {
        let items = [Self.prompt("p1"), Self.read("r1", [Self.print]), Self.text("t1", [Self.print])]
        #expect(ChatImageVisibility.visiblePaths(in: items) == ["r1": [Self.print]])
    }

    @Test func aNewUserPromptStartsANewTurn() {
        let items = [
            Self.prompt("p1"),
            Self.read("r1", [Self.print]),
            Self.prompt("p2"),
            Self.text("t2", [Self.print]),
        ]
        #expect(ChatImageVisibility.visiblePaths(in: items) == ["r1": [Self.print], "t2": [Self.print]])
    }

    @Test func repeatedPathsInOneItemCollapse() {
        let items = [Self.text("t1", [Self.print, Self.print, Self.upload])]
        #expect(ChatImageVisibility.visiblePaths(in: items) == ["t1": [Self.print, Self.upload]])
    }

    @Test func appliedReplacesThePathsWithTheVisibleOnesAndKeepsTheRest() {
        let items = [Self.prompt("p1", [Self.upload]), Self.text("t1", [Self.upload]), Self.text("t2", [])]
        let applied = ChatImageVisibility.applied(to: items)
        #expect(applied.map(\.id) == ["p1", "t1", "t2"])
        #expect(applied.map(\.imagePaths) == [[Self.upload], [], []])
        #expect(applied.map(\.kind) == items.map(\.kind))
    }

    @Test func itemsWithoutImagesAreReturnedUnchanged() {
        let items = [Self.prompt("p1"), Self.text("t1", [])]
        #expect(ChatImageVisibility.applied(to: items) == items)
    }
}
