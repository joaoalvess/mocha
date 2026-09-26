import SwiftUI

struct MarkdownTableView: View {
    let table: MarkdownTable
    let metrics: MarkdownMetrics

    static let cornerRadius: CGFloat = 10
    static let borderWidth: CGFloat = 1

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(.fitted(minimumColumnWidth: metrics.minimumColumnWidth))
            MarkdownHorizontalScroll(fadeColor: Palette.bg, showsThumb: false) {
                grid(.natural(maximumColumnWidth: metrics.maximumColumnWidth))
            }
        }
        .markdownText(metrics.table)
    }

    private func grid(_ mode: MarkdownTableLayout.Mode) -> some View {
        MarkdownTableLayout(columnCount: table.columnCount, mode: mode) {
            ForEach(table.cells) { cell in
                MarkdownTableCellView(
                    text: cell.text,
                    alignment: table.alignments[cell.column],
                    drawsTrailingRule: cell.column < table.columnCount - 1,
                    drawsBottomRule: cell.row < table.rowCount - 1
                )
            }
        }
        .padding(Self.borderWidth)
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Palette.tableBorder, lineWidth: Self.borderWidth)
        }
    }
}

struct MarkdownTableCellView: View {
    let text: AttributedString
    let alignment: MarkdownColumnAlignment
    let drawsTrailingRule: Bool
    let drawsBottomRule: Bool

    var body: some View {
        Text(text)
            .multilineTextAlignment(alignment.textAlignment)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment.frameAlignment)
            .padding(.trailing, drawsTrailingRule ? MarkdownTableView.borderWidth : 0)
            .padding(.bottom, drawsBottomRule ? MarkdownTableView.borderWidth : 0)
            .overlay(alignment: .trailing) {
                if drawsTrailingRule {
                    Rectangle()
                        .fill(Palette.tableBorder)
                        .frame(width: MarkdownTableView.borderWidth)
                }
            }
            .overlay(alignment: .bottom) {
                if drawsBottomRule {
                    Rectangle()
                        .fill(Palette.tableBorder)
                        .frame(height: MarkdownTableView.borderWidth)
                }
            }
    }
}

struct MarkdownTableLayout: Layout {
    enum Mode {
        case fitted(minimumColumnWidth: CGFloat)
        case natural(maximumColumnWidth: CGFloat)
    }

    struct Cache {
        var naturalWidths: [CGFloat]
        var measuredWidths: [CGFloat] = []
        var rowHeights: [CGFloat] = []
    }

    let columnCount: Int
    let mode: Mode

    func makeCache(subviews: Subviews) -> Cache {
        var widths = Array(repeating: CGFloat(0), count: columnCount)
        for (index, subview) in subviews.enumerated() {
            let column = index % columnCount
            widths[column] = max(widths[column], subview.sizeThatFits(.unspecified).width.rounded(.up))
        }
        return Cache(naturalWidths: widths)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let widths = columnWidths(available: proposal.width, natural: cache.naturalWidths)
        let heights = rowHeights(widths: widths, subviews: subviews, cache: &cache)
        return CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let widths = columnWidths(available: bounds.width, natural: cache.naturalWidths)
        let heights = rowHeights(widths: widths, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            var x = bounds.minX
            for (column, width) in widths.enumerated() {
                let index = row * columnCount + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: height)
                )
                x += width
            }
            y += height
        }
    }

    func columnWidths(available: CGFloat?, natural: [CGFloat]) -> [CGFloat] {
        let count = CGFloat(max(columnCount, 1))
        let total = natural.reduce(0, +)
        switch mode {
        case .natural(let maximum):
            return natural.map { min($0, maximum) }
        case .fitted(let minimum):
            guard let available, available.isFinite else {
                return total <= minimum * count ? natural : Array(repeating: minimum, count: columnCount)
            }
            let share = available / count
            if natural.allSatisfy({ $0 <= share }) {
                return Array(repeating: share, count: columnCount)
            }
            if total <= available {
                let extra = (available - total) / count
                return natural.map { $0 + extra }
            }
            return Array(repeating: share, count: columnCount)
        }
    }

    private func rowHeights(widths: [CGFloat], subviews: Subviews, cache: inout Cache) -> [CGFloat] {
        if cache.measuredWidths == widths {
            return cache.rowHeights
        }
        let rowCount = (subviews.count + columnCount - 1) / max(columnCount, 1)
        var heights = Array(repeating: CGFloat(0), count: rowCount)
        for (index, subview) in subviews.enumerated() {
            let row = index / columnCount
            let width = widths[index % columnCount]
            let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            heights[row] = max(heights[row], height)
        }
        cache.measuredWidths = widths
        cache.rowHeights = heights
        return heights
    }
}
