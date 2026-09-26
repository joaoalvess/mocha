import Foundation
import MochaClient
import MochaProtocol
import Observation

@MainActor
@Observable
final class ChatListModel {
    private(set) var rows: [ChatRow] = []
    private(set) var pending = PendingBubbles()
    private(set) var expandedRowIds: Set<String> = []

    @ObservationIgnored private var itemIds: [String] = []
    @ObservationIgnored private var items: [ChatItem] = []
    @ObservationIgnored private var rowIdByItemId: [String: String] = [:]
    @ObservationIgnored private let builder = ChatRowBuilder()

    @discardableResult
    func apply(_ newItems: [ChatItem]) -> ChatItemsChange {
        let change = ChatItemsChange.between(itemIds, newItems)
        guard change != .unchanged || newItems != items else { return change }
        items = newItems
        itemIds = newItems.map(\.id)
        let newRows = builder.rows(for: newItems)
        if newRows != rows {
            rows = newRows
            indexRows()
        }
        switch change {
        case .appended(let appended):
            pending.match(appended)
        case .replaced:
            pending.removeAll()
        case .unchanged, .prepended:
            break
        }
        return change
    }

    func pageReplaced() {
        pending.removeAll()
    }

    func addPending(_ text: String, imageCount: Int) -> PendingBubble? {
        pending.add(text, imageCount: imageCount, at: Date())
    }

    func rejectPending(_ id: PendingBubble.ID) {
        pending.markRejected(id)
    }

    func discardPending(_ id: PendingBubble.ID) {
        pending.discard(id, at: Date())
    }

    func isExpanded(_ rowId: String) -> Bool {
        expandedRowIds.contains(rowId)
    }

    var prefetchRowId: String? {
        rows.indices.contains(Self.prefetchRowIndex) ? rows[Self.prefetchRowIndex].id : nil
    }

    static let prefetchRowIndex = 8

    func spacingBelow(_ row: ChatRow) -> CGFloat {
        guard let belowId = row.toolRowBelowId, !isExpanded(row.id), !isExpanded(belowId) else { return row.spacingBelow }
        return ChatRowSpacing.betweenTools
    }

    func toggleExpansion(_ rowId: String) {
        if expandedRowIds.remove(rowId) == nil {
            expandedRowIds.insert(rowId)
        }
    }

    func expand(_ rowId: String) {
        expandedRowIds.insert(rowId)
    }

    func rowId(forItem itemId: String) -> String? {
        rowIdByItemId[itemId]
    }

    private func indexRows() {
        var index: [String: String] = [:]
        index.reserveCapacity(itemIds.count)
        for row in rows {
            switch row.content {
            case .tools(let group):
                for itemId in group.itemIds { index[itemId] = row.id }
            case .thinking(let run):
                for itemId in run.itemIds { index[itemId] = row.id }
            default:
                if index[row.id] == nil {
                    index[row.id] = row.id
                }
            }
        }
        rowIdByItemId = index
    }
}
