import MochaClient
import SwiftUI

struct AgentsCardMetrics {
    let headerSize: CGFloat
    let headlineSize: CGFloat
    let detailSize: CGFloat
    let commandSize: CGFloat
    let footnoteSize: CGFloat
    let tileSize: CGFloat
    let markSize: CGFloat
    let headerSpacing: CGFloat
    let lineSpacing: CGFloat
    let actionsSpacing: CGFloat
    let buttonHeight: CGFloat
    let gridButtonHeight: CGFloat
    let gridSpacing: CGFloat

    static let lockScreen = AgentsCardMetrics(
        headerSize: 13,
        headlineSize: 19,
        detailSize: 15,
        commandSize: 14,
        footnoteSize: 12,
        tileSize: 21,
        markSize: 17,
        headerSpacing: 4,
        lineSpacing: 2,
        actionsSpacing: 12,
        buttonHeight: 39,
        gridButtonHeight: 27,
        gridSpacing: 5
    )

    static let island = AgentsCardMetrics(
        headerSize: 13,
        headlineSize: 16,
        detailSize: 14,
        commandSize: 13,
        footnoteSize: 12,
        tileSize: 21,
        markSize: 17,
        headerSpacing: 2,
        lineSpacing: 2,
        actionsSpacing: 8,
        buttonHeight: 30,
        gridButtonHeight: 26,
        gridSpacing: 5
    )
}

struct AgentsCardTitle: View {
    let header: AgentsActivityHeader
    let metrics: AgentsCardMetrics

    var body: some View {
        HStack(spacing: 6) {
            Text(header.project)
                .foregroundStyle(AgentsPalette.labelColor(for: header.tone))
                .layoutPriority(2)
            if let model = header.model {
                separator
                Text(model)
                    .foregroundStyle(AgentsPalette.headerSecondary)
                    .layoutPriority(1)
            }
        }
        .font(.system(size: metrics.headerSize))
        .lineLimit(1)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(AgentsPalette.separator)
            .fixedSize()
    }
}

struct AgentsCardBadge: View {
    let context: AgentsActivityContext?
    let metrics: AgentsCardMetrics

    var body: some View {
        HStack(spacing: 6) {
            if let context {
                ContextBar(context: context)
            }
            ClaudeTile(size: metrics.tileSize, markSize: metrics.markSize)
        }
    }
}

struct AgentsCardHeader: View {
    let header: AgentsActivityHeader
    let metrics: AgentsCardMetrics

    var body: some View {
        HStack(spacing: 8) {
            AgentsCardTitle(header: header, metrics: metrics)
            Spacer(minLength: 0)
            AgentsCardBadge(context: header.context, metrics: metrics)
        }
        .frame(height: metrics.tileSize)
    }
}

struct AgentsCardLines: View {
    let lines: AgentsActivityLines
    let metrics: AgentsCardMetrics

    private static let headlineMinimumScale: CGFloat = 0.86
    private static let detailMinimumScale: CGFloat = 0.95

    var body: some View {
        Group {
            switch lines.detail {
            case nil:
                headline
            case .continuation:
                ViewThatFits(in: .horizontal) {
                    headline
                    VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                        headline
                        detail(lines.headline, size: metrics.detailSize, design: .default)
                    }
                }
            case .command(let command):
                VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                    headline
                    detail(command, size: metrics.commandSize, design: .monospaced)
                }
            case .text(let text):
                VStack(alignment: .leading, spacing: metrics.lineSpacing) {
                    headline
                    detail(text, size: metrics.detailSize, design: .default)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: some View {
        Text(lines.headline)
            .font(.system(size: metrics.headlineSize, weight: .bold))
            .foregroundStyle(AgentsPalette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(Self.headlineMinimumScale)
    }

    private func detail(_ text: String, size: CGFloat, design: Font.Design) -> some View {
        Text(text)
            .font(.system(size: size, design: design))
            .foregroundStyle(lines.emphasizesDetail ? AgentsPalette.waiting : AgentsPalette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(Self.detailMinimumScale)
    }
}

struct AgentsCardFootnote: View {
    let text: String
    let metrics: AgentsCardMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.footnoteSize))
            .foregroundStyle(AgentsPalette.textSecondary)
            .lineLimit(1)
    }
}
