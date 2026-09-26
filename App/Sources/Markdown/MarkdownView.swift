import SwiftUI

struct MarkdownView: View {
    let markdown: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        let cache = MarkdownDocumentCache.shared
        let metrics = cache.metrics(for: dynamicTypeSize)
        MarkdownDocumentView(document: cache.document(for: markdown, metrics: metrics), metrics: metrics)
    }
}

struct MarkdownDocumentView: View {
    let document: MarkdownDocument
    let metrics: MarkdownMetrics

    var body: some View {
        MarkdownBlocksView(blocks: document.blocks, spacing: .document, metrics: metrics)
            .markdownText(metrics.body)
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let spacing: MarkdownBlockSpacing
    let metrics: MarkdownMetrics

    var body: some View {
        if blocks.count == 1, let block = blocks.first {
            MarkdownBlockView(block: block, metrics: metrics)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block, metrics: metrics)
                        .padding(.bottom, block.id == blocks.last?.id ? 0 : spacing.after(heading: block.endsWithHeading))
                }
            }
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let metrics: MarkdownMetrics

    var body: some View {
        switch block.content {
        case .prose(let text, _):
            Text(text)
                .textSelection(.enabled)
        case .code(let text):
            MarkdownCodeBlockView(text: text, line: metrics.code)
        case .list(let list):
            MarkdownListView(list: list, metrics: metrics)
        case .quote(let blocks):
            MarkdownQuoteView(blocks: blocks, metrics: metrics)
        case .table(let table):
            MarkdownTableView(table: table, metrics: metrics)
        case .rule:
            Rectangle()
                .fill(Palette.tableBorder)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }
}

struct MarkdownListView: View {
    let list: MarkdownList
    let metrics: MarkdownMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: MarkdownBlockSpacing.listItem.after(heading: false)) {
            ForEach(list.items) { item in
                HStack(alignment: .top, spacing: 0) {
                    marker(item.marker)
                    MarkdownBlocksView(blocks: item.blocks, spacing: .listItem, metrics: metrics)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ marker: String) -> some View {
        if list.isOrdered {
            Text(verbatim: marker)
                .padding(.leading, metrics.numberInset)
                .padding(.trailing, metrics.numberGap)
        } else {
            Text(verbatim: marker)
                .padding(.leading, metrics.bulletInset)
                .frame(width: metrics.bulletColumn, alignment: .leading)
        }
    }
}

struct MarkdownQuoteView: View {
    let blocks: [MarkdownBlock]
    let metrics: MarkdownMetrics

    var body: some View {
        MarkdownBlocksView(blocks: blocks, spacing: .document, metrics: metrics)
            .foregroundStyle(Palette.textSecondary)
            .padding(.leading, metrics.quoteInset)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Palette.sepDot)
                    .frame(width: 3)
            }
    }
}
