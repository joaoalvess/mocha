import ActivityKit
import MochaClient
import MochaProtocol
import SwiftUI
import WidgetKit

struct AgentsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MochaAgentsAttributes.self) { context in
            let content = AgentsActivityContent(context.state)
            AgentsLockScreenView(content: content, isStale: context.isStale)
                .activityBackgroundTint(AgentsPalette.background)
                .activitySystemActionForegroundColor(AgentsPalette.textPrimary)
                .widgetURL(AgentsActivityText.deepLink(for: content))
        } dynamicIsland: { context in
            let content = AgentsActivityContent(context.state)
            let tone = AgentsActivityText.tone(of: content)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ClaudeTile(size: 36, markSize: 22)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let highlight = content.highlight {
                        ElapsedTimer(since: highlight.since, tone: AgentsActivityText.tone(of: highlight), size: 15)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    AgentsIslandHeader(content: content, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AgentsIslandBottom(content: content)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                ClaudeMark(size: 16, color: AgentsPalette.color(for: tone))
            } compactTrailing: {
                if let count = AgentsActivityText.compactCount(of: content) {
                    Text(count)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AgentsPalette.color(for: tone))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AgentsPalette.statusOk)
                }
            } minimal: {
                ClaudeMark(size: 16, color: AgentsPalette.color(for: tone))
            }
            .widgetURL(AgentsActivityText.deepLink(for: content))
            .keylineTint(AgentsPalette.color(for: tone))
        }
    }
}

struct AgentsLockScreenView: View {
    let content: AgentsActivityContent
    let isStale: Bool

    var body: some View {
        if let pending = content.pending {
            pendingBody(pending)
        } else {
            overview
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ClaudeTile(size: 34, markSize: 21)
                VStack(alignment: .leading, spacing: 0) {
                    SummaryText(content: content, size: 16)
                    Text(AgentsActivityText.subtitle(isStale: isStale))
                        .font(.system(size: 13))
                        .foregroundStyle(AgentsPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let highlight = content.highlight {
                AgentsPalette.divider
                    .frame(height: 1)
                    .padding(.top, 12)
                AgentsHighlightRow(highlight: highlight)
                    .padding(.top, 11)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
    }

    private func pendingBody(_ pending: AgentsActivityContent.Pending) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClaudeMark(size: 16)
                SummaryText(content: content, size: 14)
                Spacer(minLength: 8)
                if let highlight = content.highlight {
                    ElapsedTimer(since: highlight.since, tone: .waiting, size: 14)
                }
            }
            PendingActivitySection(
                pending: pending,
                workspaceLabel: workspaceLabel(for: pending),
                layout: .lockScreen
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func workspaceLabel(for pending: AgentsActivityContent.Pending) -> String? {
        guard let highlight = content.highlight, highlight.agentId == pending.agentId else { return nil }
        return highlight.workspaceLabel
    }
}

struct AgentsHighlightRow: View {
    let highlight: AgentsActivityContent.Highlight

    var body: some View {
        let tone = AgentsActivityText.tone(of: highlight)
        HStack(spacing: 10) {
            StatusDot(tone: tone)
            VStack(alignment: .leading, spacing: 0) {
                Text(highlight.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AgentsPalette.textPrimary)
                    .lineLimit(1)
                Text(AgentsActivityText.highlightDetail(highlight))
                    .font(.system(size: 13))
                    .foregroundStyle(AgentsPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ElapsedTimer(since: highlight.since, tone: tone, size: 16)
        }
    }
}

struct AgentsIslandHeader: View {
    let content: AgentsActivityContent
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SummaryText(content: content, size: 14)
            Text(content.highlight?.title ?? AgentsActivityText.subtitle(isStale: isStale))
                .font(.system(size: 12))
                .foregroundStyle(AgentsPalette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AgentsIslandBottom: View {
    let content: AgentsActivityContent

    var body: some View {
        if let pending = content.pending {
            PendingActivitySection(pending: pending, workspaceLabel: nil, layout: .island)
        } else {
            HStack(spacing: 8) {
                if let highlight = content.highlight {
                    StatusDot(tone: AgentsActivityText.tone(of: highlight))
                    Text(AgentsActivityText.highlightDetail(highlight))
                        .font(.system(size: 12))
                        .foregroundStyle(AgentsPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let url = AgentsActivityText.deepLink(for: content) {
                    Link(destination: url) {
                        Text(AgentsActivityText.open)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AgentsPalette.textPrimary)
                            .padding(.horizontal, 16)
                            .frame(height: 30)
                            .background(AgentsPalette.controlBg, in: Capsule())
                    }
                }
            }
        }
    }
}
