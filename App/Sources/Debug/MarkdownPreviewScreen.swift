#if DEBUG
import MochaClient
import MochaProtocol
import SwiftUI

enum MarkdownPreviewSection: String, CaseIterable {
    case all
    case turn
    case elements
    case blocks
    case performance = "perf"

    static let argumentKey = "preview-section"
}

struct MarkdownPreviewScreen: View {
    private let section: MarkdownPreviewSection

    init(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) {
        section = (argumentDomain[MarkdownPreviewSection.argumentKey] as? String)
            .flatMap(MarkdownPreviewSection.init(rawValue:)) ?? .all
    }

    var body: some View {
        switch section {
        case .all:
            MarkdownPreviewPage(subtitle: "turno 05b • elementos • blocos") {
                MarkdownPreviewTurnItems()
                MarkdownView(markdown: MarkdownPreviewSamples.elements)
                MarkdownView(markdown: MarkdownPreviewSamples.blocks)
            }
        case .turn:
            MarkdownPreviewTurn()
        case .elements:
            MarkdownPreviewPage(subtitle: "texto • títulos • listas • citação") {
                MarkdownView(markdown: MarkdownPreviewSamples.elements)
            }
        case .blocks:
            MarkdownPreviewPage(subtitle: "código • tabelas • régua • html") {
                MarkdownView(markdown: MarkdownPreviewSamples.blocks)
            }
        case .performance:
            MarkdownPreviewPerformance()
        }
    }
}

private struct MarkdownPreviewTurn: View {
    static let contentBottom: CGFloat = 107

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Metrics.listItemSpacing) {
                MarkdownPreviewTurnItems()
            }
            .padding(.horizontal, Metrics.contentMargin)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, Self.contentBottom)
            .ignoresSafeArea()
            MarkdownPreviewChrome(title: MarkdownPreviewSamples.turnTitle, subtitle: MarkdownPreviewSamples.turnSubtitle)
        }
    }
}

private struct MarkdownPreviewTurnItems: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let metrics = MarkdownDocumentCache.shared.metrics(for: dynamicTypeSize)
        VStack(spacing: 6) {
            ForEach(MarkdownPreviewSamples.turnTools, id: \.self) { command in
                ToolCallCard(icon: .shell, name: "Shell", count: 1, summary: command, status: .succeeded)
            }
        }
        MarkdownView(markdown: MarkdownPreviewSamples.turn)
        Text(verbatim: MarkdownPreviewSamples.turnFooter)
            .markdownText(metrics.body, face: .italic)
            .foregroundStyle(Palette.textSecondary)
        Text(recap(metrics.body))
            .markdownText(metrics.body, face: .italic)
            .foregroundStyle(Palette.textSecondary)
    }

    private func recap(_ line: MarkdownLineMetrics) -> AttributedString {
        var label = AttributedString("Recap:")
        label.font = line.font(.boldItalic)
        return label + AttributedString(" " + MarkdownPreviewSamples.turnRecap)
    }
}

private struct MarkdownPreviewPage<Content: View>: View {
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.listItemSpacing) {
                content()
            }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.vertical, Metrics.listItemSpacing)
        }
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ChatHeaderBar(indicator: .agent(.idle), title: "Markdown", subtitle: subtitle)
                .padding(.horizontal, Metrics.floatingMargin)
                .padding(.top, Metrics.headerTopInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CollapsedComposer(draft: "")
                .padding(.horizontal, Metrics.floatingMargin)
                .padding(.bottom, Metrics.composerBottomInset)
        }
    }
}

private struct MarkdownPreviewChrome: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderBar(indicator: .agent(.idle), title: title, subtitle: subtitle)
                .padding(.horizontal, Metrics.floatingMargin)
                .padding(.top, Metrics.headerTopInset)
            Spacer()
            CollapsedComposer(draft: "")
                .padding(.horizontal, Metrics.floatingMargin)
                .padding(.bottom, Metrics.composerBottomInset)
        }
    }
}
#endif
