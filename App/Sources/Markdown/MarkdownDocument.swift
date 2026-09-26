import SwiftUI

struct MarkdownDocument: Sendable {
    let blocks: [MarkdownBlock]
}

struct MarkdownBlock: Identifiable, Sendable {
    let id: Int
    let content: MarkdownBlockContent

    var endsWithHeading: Bool {
        if case .prose(_, let endsWithHeading) = content { endsWithHeading } else { false }
    }
}

enum MarkdownBlockSpacing: Sendable {
    case document
    case listItem

    func after(heading: Bool) -> CGFloat {
        switch self {
        case .document: heading ? 8 : 12
        case .listItem: 4
        }
    }
}

enum MarkdownBlockContent: Sendable {
    case prose(AttributedString, endsWithHeading: Bool)
    case code(AttributedString)
    case list(MarkdownList)
    case quote([MarkdownBlock])
    case table(MarkdownTable)
    case rule
}

struct MarkdownList: Sendable {
    let isOrdered: Bool
    let items: [MarkdownListItem]
}

struct MarkdownListItem: Identifiable, Sendable {
    let id: Int
    let marker: String
    let blocks: [MarkdownBlock]
}

enum MarkdownColumnAlignment: Sendable {
    case leading
    case center
    case trailing

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }
}

struct MarkdownTableCell: Identifiable, Sendable {
    let id: Int
    let row: Int
    let column: Int
    let text: AttributedString
}

struct MarkdownTable: Sendable {
    let columnCount: Int
    let rowCount: Int
    let alignments: [MarkdownColumnAlignment]
    let cells: [MarkdownTableCell]
}
