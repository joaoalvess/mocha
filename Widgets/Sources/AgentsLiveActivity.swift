import ActivityKit
import MochaClient
import MochaProtocol
import SwiftUI
import WidgetKit

struct AgentsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MochaAgentAttributes.self) { context in
            let content = AgentsActivityContent(context.state)
            AgentsLockScreenView(content: content, agentId: context.attributes.agentId, isStale: context.isStale)
                .activityBackgroundTint(AgentsPalette.background)
                .activitySystemActionForegroundColor(AgentsPalette.textPrimary)
                .widgetURL(AgentsActivityText.deepLink(forAgent: context.attributes.agentId))
        } dynamicIsland: { context in
            let content = AgentsActivityContent(context.state)
            let header = AgentsActivityText.header(of: content)
            let tone = AgentsActivityText.tone(of: content)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentsCardTitle(header: header, metrics: .island)
                        .frame(height: AgentsCardMetrics.island.tileSize)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AgentsCardBadge(context: header.context, metrics: .island)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AgentsIslandBody(content: content, agentId: context.attributes.agentId, isStale: context.isStale)
                        .padding(.horizontal, 6)
                }
            } compactLeading: {
                ClaudeMark(size: 16, color: AgentsPalette.color(for: tone))
            } compactTrailing: {
                Text(header.project)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AgentsPalette.labelColor(for: tone))
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                ClaudeMark(size: 16, color: AgentsPalette.color(for: tone))
            }
            .widgetURL(AgentsActivityText.deepLink(forAgent: context.attributes.agentId))
            .keylineTint(AgentsPalette.color(for: tone))
        }
    }
}

struct AgentsLockScreenView: View {
    let content: AgentsActivityContent
    let agentId: String
    let isStale: Bool

    private let metrics = AgentsCardMetrics.lockScreen

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.lineSpacing) {
            AgentsCardHeader(header: AgentsActivityText.header(of: content), metrics: metrics)
            AgentsCardLines(lines: AgentsActivityText.lines(of: content), metrics: metrics)
                .padding(.top, metrics.headerSpacing - metrics.lineSpacing)
            if let footnote = AgentsActivityText.footnote(isStale: isStale) {
                AgentsCardFootnote(text: footnote, metrics: metrics)
            }
            if let pending = content.pending {
                PendingActivityControls(pending: pending, agentId: agentId, metrics: metrics)
                    .padding(.top, metrics.actionsSpacing - metrics.lineSpacing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 16)
    }
}

struct AgentsIslandBody: View {
    let content: AgentsActivityContent
    let agentId: String
    let isStale: Bool

    private let metrics = AgentsCardMetrics.island

    var body: some View {
        let footnote = AgentsActivityText.footnote(isStale: isStale)
        let openURL = AgentsActivityText.deepLink(forAgent: agentId)
        VStack(alignment: .leading, spacing: metrics.lineSpacing) {
            AgentsCardLines(lines: AgentsActivityText.lines(of: content), metrics: metrics)
            if let pending = content.pending {
                if let footnote {
                    AgentsCardFootnote(text: footnote, metrics: metrics)
                }
                PendingActivityControls(pending: pending, agentId: agentId, metrics: metrics)
                    .padding(.top, metrics.actionsSpacing - metrics.lineSpacing)
            } else if footnote != nil || openURL != nil {
                HStack(spacing: 8) {
                    if let footnote {
                        AgentsCardFootnote(text: footnote, metrics: metrics)
                    }
                    Spacer(minLength: 8)
                    if let openURL {
                        OpenAgentButton(url: openURL, height: metrics.buttonHeight)
                    }
                }
                .padding(.top, metrics.actionsSpacing - metrics.lineSpacing)
            }
        }
    }
}

struct OpenAgentButton: View {
    let url: URL
    let height: CGFloat

    var body: some View {
        Link(destination: url) {
            Text(AgentsActivityText.open)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AgentsPalette.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: height)
                .background(AgentsPalette.controlBg, in: Capsule())
        }
    }
}
