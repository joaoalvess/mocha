import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct PendingBubblesTests {
    private static let sentAt = Date(timeIntervalSince1970: 1_790_337_600)

    private static func prompt(_ text: String, imageCount: Int = 0, id: String = UUID().uuidString) -> ChatItem {
        ChatItem(id: id, at: sentAt, kind: .userPrompt(text: text, imageCount: imageCount))
    }

    private static func slash(_ name: String, _ args: String = "", id: String = UUID().uuidString) -> ChatItem {
        ChatItem(id: id, at: sentAt, kind: .slashCommand(name: name, args: args, output: nil))
    }

    @Test func addTrimsTheTextAndIgnoresBlankOnes() {
        var pending = PendingBubbles()
        let added = pending.add("  roda os testes \n", at: Self.sentAt)
        let blank = pending.add(" \n ", at: Self.sentAt)
        #expect(added?.text == "roda os testes")
        #expect(blank == nil)
        #expect(pending.bubbles.map(\.text) == ["roda os testes"])
    }

    @Test func bubbleWithImagesAcceptsAnEmptyText() throws {
        var pending = PendingBubbles()
        let imageOnlyAdded = pending.add(" ", imageCount: 2, at: Self.sentAt)
        let withTextAdded = pending.add("olha isso ", imageCount: 1, at: Self.sentAt)
        let imageOnly = try #require(imageOnlyAdded)
        let withText = try #require(withTextAdded)
        #expect(imageOnly.text.isEmpty)
        #expect(imageOnly.imageCount == 2)
        #expect(withText.text == "olha isso")
        #expect(withText.imageCount == 1)
    }

    @Test func promptWithImagesMatchesByTextAndImageCount() {
        var pending = PendingBubbles()
        pending.add("", imageCount: 2, at: Self.sentAt)
        pending.add("olha isso", imageCount: 1, at: Self.sentAt)
        pending.match([Self.prompt("", imageCount: 1), Self.prompt("olha isso", imageCount: 0)])
        #expect(pending.bubbles.count == 2)
        pending.match([Self.prompt("olha isso\n", imageCount: 1), Self.prompt("", imageCount: 2)])
        #expect(pending.isEmpty)
    }

    @Test func bubbleWithImagesNeverMatchesASlashCommand() {
        var pending = PendingBubbles()
        pending.add("/compact", imageCount: 1, at: Self.sentAt)
        pending.match([Self.slash("/compact")])
        #expect(pending.bubbles.count == 1)
    }

    @Test func promptMatchesTheOldestBubbleWithTheSameTextFirst() {
        var pending = PendingBubbles()
        let first = pending.add("ok", at: Self.sentAt)
        let second = pending.add("ok", at: Self.sentAt.addingTimeInterval(1))
        let item = Self.prompt("ok")
        let matched = pending.match([item])
        #expect(matched.map(\.bubbleId) == [first?.id].compactMap { $0 })
        #expect(matched.map(\.item) == [item])
        #expect(pending.bubbles.map(\.id) == [second?.id].compactMap { $0 })
    }

    @Test func promptsMatchInOrderOfArrival() {
        var pending = PendingBubbles()
        pending.add("primeiro", at: Self.sentAt)
        pending.add("segundo", at: Self.sentAt)
        pending.add("terceiro", at: Self.sentAt)
        pending.match([Self.prompt("primeiro"), Self.prompt("segundo")])
        #expect(pending.bubbles.map(\.text) == ["terceiro"])
    }

    @Test func eachItemConsumesOneBubble() {
        var pending = PendingBubbles()
        pending.add("ok", at: Self.sentAt)
        pending.add("ok", at: Self.sentAt)
        pending.match([Self.prompt("ok")])
        #expect(pending.bubbles.count == 1)
    }

    @Test func matchIgnoresSurroundingWhitespace() {
        var pending = PendingBubbles()
        pending.add("  troca a paginação  ", at: Self.sentAt)
        pending.match([Self.prompt("\ntroca a paginação\n")])
        #expect(pending.isEmpty)
    }

    @Test func promptFromTheTerminalKeepsTheBubbles() {
        var pending = PendingBubbles()
        pending.add("do app", at: Self.sentAt)
        pending.match([Self.prompt("do terminal"), ChatItem(id: "t", at: Self.sentAt, kind: .assistantText(markdown: "do app"))])
        #expect(pending.bubbles.map(\.text) == ["do app"])
    }

    @Test(arguments: [
        ("/compact", "/compact", ""),
        ("/compact  foco nos testes ", "/compact", "foco nos testes"),
        ("/clear", "/clear", ""),
        ("!git status --short", "!", "git status --short"),
        ("! git status --short", "!", "git status --short"),
    ])
    func commandTextMatchesSlashCommand(sent: String, name: String, args: String) {
        var pending = PendingBubbles()
        pending.add(sent, at: Self.sentAt)
        pending.match([Self.slash(name, args)])
        #expect(pending.isEmpty)
    }

    @Test func plainTextDoesNotMatchASlashCommand() {
        var pending = PendingBubbles()
        pending.add("compact", at: Self.sentAt)
        pending.match([Self.slash("/compact")])
        #expect(pending.bubbles.count == 1)
    }

    @Test func commandTextDoesNotMatchAnotherCommand() {
        var pending = PendingBubbles()
        pending.add("/compact", at: Self.sentAt)
        pending.add("!ls", at: Self.sentAt)
        pending.match([Self.slash("/context"), Self.slash("!", "pwd")])
        #expect(pending.bubbles.map(\.text) == ["/compact", "!ls"])
    }

    @Test func textStartingWithSlashStillMatchesAPlainPrompt() {
        var pending = PendingBubbles()
        pending.add("/Users/dev/app.swift explica esse arquivo", at: Self.sentAt)
        pending.match([Self.prompt("/Users/dev/app.swift explica esse arquivo")])
        #expect(pending.isEmpty)
    }

    @Test func bubbleTurnsUnconfirmedAfterSixtySeconds() throws {
        var pending = PendingBubbles()
        let bubbleAdded = pending.add("ok", at: Self.sentAt)
        let bubble = try #require(bubbleAdded)
        #expect(!bubble.isUnconfirmed(at: Self.sentAt.addingTimeInterval(59.9)))
        #expect(bubble.isUnconfirmed(at: Self.sentAt.addingTimeInterval(60)))
        #expect(bubble.confirmationDeadline == Self.sentAt.addingTimeInterval(60))
    }

    @Test func onlyUnconfirmedBubblesCanBeDiscarded() throws {
        var pending = PendingBubbles()
        let bubbleAdded = pending.add("ok", at: Self.sentAt)
        let bubble = try #require(bubbleAdded)
        let early = pending.discard(bubble.id, at: Self.sentAt.addingTimeInterval(30))
        #expect(!early)
        #expect(pending.bubbles.count == 1)
        let late = pending.discard(bubble.id, at: Self.sentAt.addingTimeInterval(61))
        #expect(late)
        #expect(pending.isEmpty)
    }

    @Test func rejectedBubbleIsUnconfirmedRightAway() throws {
        var pending = PendingBubbles()
        let bubbleAdded = pending.add("ok", at: Self.sentAt)
        let bubble = try #require(bubbleAdded)
        pending.markRejected(bubble.id)
        #expect(pending.bubbles.first?.isUnconfirmed(at: Self.sentAt) == true)
        let discarded = pending.discard(bubble.id, at: Self.sentAt)
        #expect(discarded)
    }

    @Test func lateEchoStillMatchesAnUnconfirmedBubble() {
        var pending = PendingBubbles()
        let added = pending.add("ok", at: Self.sentAt)
        pending.markRejected(added?.id ?? 0)
        pending.match([Self.prompt("ok")])
        #expect(pending.isEmpty)
    }

    @Test func removeAllClearsEverything() {
        var pending = PendingBubbles()
        pending.add("a", at: Self.sentAt)
        pending.add("b", at: Self.sentAt)
        pending.removeAll()
        #expect(pending.isEmpty)
    }

    @Test func idsKeepGrowingAfterRemoval() throws {
        var pending = PendingBubbles()
        let firstAdded = pending.add("a", at: Self.sentAt)
        let first = try #require(firstAdded)
        pending.removeAll()
        let secondAdded = pending.add("a", at: Self.sentAt)
        let second = try #require(secondAdded)
        #expect(second.id != first.id)
    }
}

struct ChatItemsChangeTests {
    private static let at = Date(timeIntervalSince1970: 1_790_337_600)

    private static func items(_ ids: [String]) -> [ChatItem] {
        ids.map { ChatItem(id: $0, at: at, kind: .notice(text: $0)) }
    }

    @Test func firstPageIsAReplacement() {
        #expect(ChatItemsChange.between([], Self.items(["a"])) == .replaced)
        #expect(ChatItemsChange.between([], []) == .unchanged)
    }

    @Test func sameIdsAreUnchanged() {
        #expect(ChatItemsChange.between(["a", "b"], Self.items(["a", "b"])) == .unchanged)
    }

    @Test func newItemsAtTheEndAreAppended() {
        #expect(ChatItemsChange.between(["a", "b"], Self.items(["a", "b", "c", "d"])) == .appended(Self.items(["c", "d"])))
    }

    @Test func olderItemsAtTheStartArePrepended() {
        #expect(ChatItemsChange.between(["c", "d"], Self.items(["a", "b", "c", "d"])) == .prepended(count: 2))
    }

    @Test func anythingElseIsAReplacement() {
        #expect(ChatItemsChange.between(["a", "b"], Self.items(["b", "c"])) == .replaced)
        #expect(ChatItemsChange.between(["a", "b", "c"], Self.items(["x"])) == .replaced)
        #expect(ChatItemsChange.between(["a", "b"], Self.items(["x", "a", "y", "b"])) == .replaced)
        #expect(ChatItemsChange.between(["a"], []) == .replaced)
    }
}
