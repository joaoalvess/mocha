import Foundation
import MochaProtocol

public enum TranscriptChange: Sendable, Equatable {
    case append(ChatItem)
    case update(ChatItem)

    public var item: ChatItem {
        switch self {
        case .append(let item), .update(let item): item
        }
    }
}

public struct TranscriptChangeBatch: Sendable, Equatable {
    public private(set) var updated: [ChatItem] = []
    public private(set) var appended: [ChatItem] = []
    private var appendedPositions: [String: Int] = [:]
    private var updatedPositions: [String: Int] = [:]

    public init(_ changes: [TranscriptChange] = []) {
        for change in changes {
            add(change)
        }
    }

    public var isEmpty: Bool {
        updated.isEmpty && appended.isEmpty
    }

    public mutating func add(_ change: TranscriptChange) {
        switch change {
        case .append(let item):
            appendedPositions[item.id] = appended.count
            appended.append(item)
        case .update(let item):
            if let position = appendedPositions[item.id] {
                appended[position] = item
            } else if let position = updatedPositions[item.id] {
                updated[position] = item
            } else {
                updatedPositions[item.id] = updated.count
                updated.append(item)
            }
        }
    }
}

public struct ChatItemList: Sendable, Equatable {
    public private(set) var items: [ChatItem] = []
    private var positions: [String: Int] = [:]

    public init(_ items: [ChatItem] = []) {
        for item in items {
            apply(.append(item))
        }
    }

    public func contains(id: String) -> Bool {
        positions[id] != nil
    }

    @discardableResult
    public mutating func apply(_ change: TranscriptChange) -> Bool {
        switch change {
        case .append(let item):
            positions[item.id] = items.count
            items.append(item)
            return true
        case .update(let item):
            guard let position = positions[item.id] else { return false }
            items[position] = item
            return true
        }
    }
}
