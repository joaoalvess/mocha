import Accessibility
import CoreText
import Foundation
import Markdown
import SwiftUI

struct MarkdownParser {
    static let options: ParseOptions = [.disableSmartOpts, .disableSourcePosOpts]

    private let metrics: MarkdownMetrics
    private var nextID = 0

    private init(metrics: MarkdownMetrics) {
        self.metrics = metrics
    }

    static func parse(_ source: String, metrics: MarkdownMetrics) -> MarkdownDocument {
        let document = Document(parsing: source, options: options)
        var parser = MarkdownParser(metrics: metrics)
        return MarkdownDocument(blocks: parser.blocks(from: document.children, spacing: .document, listDepth: 0))
    }

    private mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private mutating func block(_ content: MarkdownBlockContent) -> MarkdownBlock {
        MarkdownBlock(id: makeID(), content: content)
    }

    private mutating func blocks(from children: MarkupChildren, spacing: MarkdownBlockSpacing, listDepth: Int) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var prose = MarkdownProseBuilder(metrics: metrics, spacing: spacing)
        for child in children {
            append(child, listDepth: listDepth, prose: &prose, to: &result)
        }
        flush(&prose, into: &result)
        return result
    }

    private mutating func flush(_ prose: inout MarkdownProseBuilder, into result: inout [MarkdownBlock]) {
        guard let content = prose.take() else { return }
        result.append(block(content))
    }

    private mutating func append(
        _ markup: Markup,
        listDepth: Int,
        prose: inout MarkdownProseBuilder,
        to result: inout [MarkdownBlock]
    ) {
        switch markup {
        case let paragraph as Paragraph:
            prose.append(MarkdownInlineBuilder.attributed(paragraph.children, style: .body, metrics: metrics))
        case let heading as Heading:
            prose.append(MarkdownInlineBuilder.attributed(heading.children, style: .heading, metrics: metrics), headingLevel: heading.level)
        case let html as HTMLBlock:
            let text = html.rawHTML.trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                prose.append(MarkdownInlineBuilder.plain(text, style: .body, metrics: metrics))
            }
        case let code as CodeBlock:
            flush(&prose, into: &result)
            result.append(block(.code(MarkdownCodeHighlighter.attributed(code.code, language: code.language))))
        case let list as UnorderedList:
            flush(&prose, into: &result)
            let content = self.list(Array(list.listItems), isOrdered: false, start: 1, depth: listDepth)
            result.append(block(.list(content)))
        case let list as OrderedList:
            flush(&prose, into: &result)
            let content = self.list(Array(list.listItems), isOrdered: true, start: Int(list.startIndex), depth: listDepth)
            result.append(block(.list(content)))
        case let quote as BlockQuote:
            flush(&prose, into: &result)
            let content = blocks(from: quote.children, spacing: .document, listDepth: listDepth)
            result.append(block(.quote(content)))
        case let table as Markdown.Table:
            flush(&prose, into: &result)
            let content = self.table(table)
            result.append(block(.table(content)))
        case is ThematicBreak:
            flush(&prose, into: &result)
            result.append(block(.rule))
        default:
            for child in markup.children {
                append(child, listDepth: listDepth, prose: &prose, to: &result)
            }
        }
    }

    private mutating func list(_ items: [ListItem], isOrdered: Bool, start: Int, depth: Int) -> MarkdownList {
        let markers = isOrdered
            ? Self.orderedMarkers(count: items.count, start: start)
            : Array(repeating: depth.isMultiple(of: 2) ? "•" : "◦", count: items.count)
        var listItems: [MarkdownListItem] = []
        listItems.reserveCapacity(items.count)
        for (item, marker) in zip(items, markers) {
            var content = blocks(from: item.children, spacing: .listItem, listDepth: depth + 1)
            if let checkbox = item.checkbox {
                content = prefixed(content, with: checkbox == .checked ? "[x] " : "[ ] ")
            }
            listItems.append(MarkdownListItem(id: makeID(), marker: marker, blocks: content))
        }
        return MarkdownList(isOrdered: isOrdered, items: listItems)
    }

    private mutating func prefixed(_ content: [MarkdownBlock], with prefix: String) -> [MarkdownBlock] {
        var marker = AttributedString(prefix)
        marker.foregroundColor = Palette.textSecondary
        guard let first = content.first, case .prose(let text, let endsWithHeading) = first.content else {
            marker[MarkdownLineHeightKey.self] = metrics.body.lineHeight
            return [block(.prose(marker, endsWithHeading: false))] + content
        }
        marker[MarkdownLineHeightKey.self] = text.runs.first?[MarkdownLineHeightKey.self] ?? metrics.body.lineHeight
        return [MarkdownBlock(id: first.id, content: .prose(marker + text, endsWithHeading: endsWithHeading))] + content.dropFirst()
    }

    static func orderedMarkers(count: Int, start: Int) -> [String] {
        let labels = (0..<count).map { "\(start + $0)." }
        let width = labels.map(\.count).max() ?? 0
        return labels.map { String(repeating: " ", count: width - $0.count) + $0 }
    }

    private mutating func table(_ table: Markdown.Table) -> MarkdownTable {
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        let columnCount = max(table.maxColumnCount, 1)
        var cells: [MarkdownTableCell] = []
        cells.reserveCapacity(rows.count * columnCount)
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columnCount {
                let text = column < row.count
                    ? MarkdownInlineBuilder.attributed(row[column].children, style: .table, metrics: metrics, bold: rowIndex == 0)
                    : AttributedString()
                cells.append(MarkdownTableCell(id: makeID(), row: rowIndex, column: column, text: text))
            }
        }
        let declared = table.columnAlignments
        let alignments = (0..<columnCount).map { column in
            column < declared.count ? Self.alignment(declared[column]) : .leading
        }
        return MarkdownTable(columnCount: columnCount, rowCount: rows.count, alignments: alignments, cells: cells)
    }

    private static func alignment(_ alignment: Markdown.Table.ColumnAlignment?) -> MarkdownColumnAlignment {
        switch alignment {
        case .center: .center
        case .right: .trailing
        case .left, nil: .leading
        }
    }
}

struct MarkdownProseBuilder {
    private let metrics: MarkdownMetrics
    private let spacing: MarkdownBlockSpacing
    private var text = AttributedString()
    private var isEmpty = true
    private var endsWithHeading = false
    private var lastLineHeight: MarkdownLineHeightKey.Value?

    init(metrics: MarkdownMetrics, spacing: MarkdownBlockSpacing) {
        self.metrics = metrics
        self.spacing = spacing
    }

    mutating func append(_ paragraph: AttributedString, headingLevel: Int? = nil) {
        if !isEmpty {
            var terminator = AttributedString("\n")
            terminator[MarkdownLineHeightKey.self] = lastLineHeight
            var spacer = AttributedString("\n")
            spacer[MarkdownLineHeightKey.self] = .exact(points: spacing.after(heading: endsWithHeading))
            text.append(terminator)
            text.append(spacer)
        }
        var paragraph = paragraph
        let lineHeight = headingLevel == nil ? metrics.body.lineHeight : metrics.heading.lineHeight
        paragraph[MarkdownLineHeightKey.self] = lineHeight
        if let headingLevel {
            paragraph[MarkdownHeadingLevelKey.self] = MarkdownHeadingLevelKey.Value(rawValue: min(headingLevel, 6)) ?? .unspecified
        }
        text.append(paragraph)
        isEmpty = false
        endsWithHeading = headingLevel != nil
        lastLineHeight = lineHeight
    }

    mutating func take() -> MarkdownBlockContent? {
        guard !isEmpty else { return nil }
        let content = MarkdownBlockContent.prose(text, endsWithHeading: endsWithHeading)
        self = MarkdownProseBuilder(metrics: metrics, spacing: spacing)
        return content
    }
}

struct MarkdownInlineBuilder {
    private struct Traits {
        var bold: Bool
        var italic = false
        var strikethrough = false
        var isLink = false
        var url: URL?
    }

    private let style: MarkdownTextStyle
    private let line: MarkdownLineMetrics
    private var output = AttributedString()

    private init(style: MarkdownTextStyle, metrics: MarkdownMetrics) {
        self.style = style
        line = metrics.line(style)
    }

    static func attributed(
        _ children: MarkupChildren,
        style: MarkdownTextStyle,
        metrics: MarkdownMetrics,
        bold: Bool = false
    ) -> AttributedString {
        var builder = MarkdownInlineBuilder(style: style, metrics: metrics)
        builder.append(children, traits: Traits(bold: bold || style.isBold))
        return builder.output
    }

    static func plain(_ text: String, style: MarkdownTextStyle, metrics: MarkdownMetrics) -> AttributedString {
        var builder = MarkdownInlineBuilder(style: style, metrics: metrics)
        builder.appendRun(text, traits: Traits(bold: style.isBold))
        return builder.output
    }

    private mutating func append(_ children: MarkupChildren, traits: Traits) {
        for child in children {
            append(child, traits: traits)
        }
    }

    private mutating func append(_ markup: Markup, traits: Traits) {
        var traits = traits
        switch markup {
        case let text as Markdown.Text:
            appendRun(text.string, traits: traits)
        case let emphasis as Emphasis:
            traits.italic = true
            append(emphasis.children, traits: traits)
        case let strong as Strong:
            traits.bold = true
            append(strong.children, traits: traits)
        case let strikethrough as Strikethrough:
            traits.strikethrough = true
            append(strikethrough.children, traits: traits)
        case let code as InlineCode:
            appendRun(code.code, traits: traits, color: Palette.link)
        case let link as Markdown.Link:
            traits.isLink = true
            traits.url = link.destination.flatMap(URL.init(string:))
            append(link.children, traits: traits)
        case let image as Markdown.Image:
            traits.isLink = true
            traits.url = image.source.flatMap(URL.init(string:))
            let alt = image.plainText
            appendRun(alt.isEmpty ? image.source ?? "" : alt, traits: traits)
        case is SoftBreak:
            appendRun(" ", traits: traits)
        case is LineBreak:
            appendRun("\n", traits: traits)
        case let html as InlineHTML:
            appendRun(Self.isLineBreakTag(html.rawHTML) ? "\n" : html.rawHTML, traits: traits)
        case let symbol as SymbolLink:
            appendRun(symbol.destination ?? "", traits: traits, color: Palette.link)
        default:
            if markup.childCount > 0 {
                append(markup.children, traits: traits)
            } else if let plain = markup as? PlainTextConvertibleMarkup {
                appendRun(plain.plainText, traits: traits)
            }
        }
    }

    private mutating func appendRun(_ string: String, traits: Traits, color: Color? = nil) {
        guard !string.isEmpty else { return }
        var run = AttributedString(string)
        let face = MonoFace.face(bold: traits.bold, italic: traits.italic)
        if face != .regular || !style.inheritsFont {
            run.font = line.font(face)
        }
        if let color {
            run.foregroundColor = color
        }
        if traits.isLink {
            run.foregroundColor = Palette.link
            run.underlineStyle = .single
            run.link = traits.url
        }
        if traits.strikethrough {
            run.strikethroughStyle = .single
        }
        output.append(run)
    }

    private static func isLineBreakTag(_ html: String) -> Bool {
        let tag = html.lowercased().filter { !$0.isWhitespace }
        return tag == "<br>" || tag == "<br/>"
    }
}

enum MarkdownCodeHighlighter {
    static let hashCommentLanguages: Set<String> = [
        "sh", "bash", "zsh", "fish", "shell", "console", "python", "py", "ruby", "rb",
        "yaml", "yml", "toml", "dockerfile", "makefile", "make", "perl", "r",
    ]

    static func attributed(_ code: String, language: String?) -> AttributedString {
        var source = Substring(code)
        while source.last?.isNewline == true {
            source = source.dropLast()
        }
        let usesHashComments = language
            .flatMap { $0.split(separator: " ").first }
            .map { hashCommentLanguages.contains($0.lowercased()) } ?? false
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var output = AttributedString()
        for (index, line) in lines.enumerated() {
            let expanded = line.replacingOccurrences(of: "\t", with: "    ")
            var run = AttributedString(index == lines.count - 1 ? expanded : expanded + "\n")
            if isComment(line, usesHashComments: usesHashComments) {
                run.foregroundColor = Palette.textSecondary
            }
            output.append(run)
        }
        return output
    }

    private static func isComment(_ line: Substring, usesHashComments: Bool) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return trimmed.hasPrefix("//") || (usesHashComments && trimmed.hasPrefix("#"))
    }
}
