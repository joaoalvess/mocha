import Foundation
import MochaProtocol

public struct PendingBubble: Sendable, Hashable, Identifiable {
    public let id: Int
    public let text: String
    public let imageCount: Int
    public let sentAt: Date
    public fileprivate(set) var isRejected = false

    public var confirmationDeadline: Date {
        sentAt.addingTimeInterval(PendingBubbles.confirmationTimeout)
    }

    public func isUnconfirmed(at now: Date) -> Bool {
        isRejected || now >= confirmationDeadline
    }
}

public struct PendingMatch: Sendable, Hashable {
    public let bubbleId: PendingBubble.ID
    public let item: ChatItem
}

public struct PendingBubbles: Sendable, Hashable {
    public static let confirmationTimeout: TimeInterval = 60

    public private(set) var bubbles: [PendingBubble] = []
    private var nextId = 0

    public init() {}

    public var isEmpty: Bool { bubbles.isEmpty }

    @discardableResult
    public mutating func add(_ text: String, imageCount: Int = 0, at date: Date) -> PendingBubble? {
        let text = Self.trimmed(text)
        guard !text.isEmpty || imageCount > 0 else { return nil }
        nextId += 1
        let bubble = PendingBubble(id: nextId, text: text, imageCount: max(0, imageCount), sentAt: date)
        bubbles.append(bubble)
        return bubble
    }

    @discardableResult
    public mutating func match(_ items: [ChatItem]) -> [PendingMatch] {
        var matched: [PendingMatch] = []
        for item in items {
            guard let index = bubbles.firstIndex(where: { Self.matches($0, item.kind) }) else { continue }
            matched.append(PendingMatch(bubbleId: bubbles.remove(at: index).id, item: item))
        }
        return matched
    }

    public mutating func markRejected(_ id: PendingBubble.ID) {
        guard let index = bubbles.firstIndex(where: { $0.id == id }) else { return }
        bubbles[index].isRejected = true
    }

    @discardableResult
    public mutating func discard(_ id: PendingBubble.ID, at now: Date) -> Bool {
        guard let index = bubbles.firstIndex(where: { $0.id == id }), bubbles[index].isUnconfirmed(at: now) else { return false }
        bubbles.remove(at: index)
        return true
    }

    public mutating func removeAll() {
        bubbles.removeAll()
    }

    static func matches(_ bubble: PendingBubble, _ kind: ChatItemKind) -> Bool {
        switch kind {
        case .userPrompt(let text, let imageCount):
            return trimmed(text) == bubble.text && imageCount == bubble.imageCount
        case .slashCommand(let name, let args, _):
            guard bubble.imageCount == 0, let command = commandKey(forSent: bubble.text) else { return false }
            return command == commandKey(name: name, args: args)
        default:
            return false
        }
    }

    private static func commandKey(forSent text: String) -> String? {
        if text.hasPrefix(shellPrefix) {
            return shellPrefix + trimmed(String(text.dropFirst()))
        }
        guard text.hasPrefix(slashPrefix) else { return nil }
        let name = text.prefix { !$0.isWhitespace }
        return joined(String(name), String(text.dropFirst(name.count)))
    }

    private static func commandKey(name: String, args: String) -> String {
        name == shellPrefix ? shellPrefix + trimmed(args) : joined(name, args)
    }

    private static func joined(_ name: String, _ args: String) -> String {
        let args = trimmed(args)
        return args.isEmpty ? name : name + " " + args
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let shellPrefix = "!"
    private static let slashPrefix = "/"
}

public enum ChatItemsChange: Sendable, Equatable {
    case unchanged
    case appended([ChatItem])
    case prepended(count: Int)
    case replaced

    public static func between(_ previousIds: [String], _ items: [ChatItem]) -> ChatItemsChange {
        if previousIds.isEmpty {
            return items.isEmpty ? .unchanged : .replaced
        }
        guard items.count >= previousIds.count else { return .replaced }
        if items.count == previousIds.count {
            return zip(items, previousIds).allSatisfy { $0.id == $1 } ? .unchanged : .replaced
        }
        if zip(items, previousIds).allSatisfy({ $0.id == $1 }) {
            return .appended(Array(items.dropFirst(previousIds.count)))
        }
        let added = items.count - previousIds.count
        if zip(items.dropFirst(added), previousIds).allSatisfy({ $0.id == $1 }) {
            return .prepended(count: added)
        }
        return .replaced
    }
}
