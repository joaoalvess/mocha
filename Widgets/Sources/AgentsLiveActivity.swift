import ActivityKit
import MochaProtocol
import SwiftUI
import WidgetKit

struct AgentsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MochaAgentsAttributes.self) { context in
            AgentsLockScreenView(state: context.state)
                .activityBackgroundTint(AgentsPalette.background)
                .activitySystemActionForegroundColor(AgentsPalette.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentsAsterisk(state: context.state)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let highlight = context.state.highlight {
                        Text(timerInterval: highlight.since...Date.distantFuture, countsDown: false)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 56, alignment: .trailing)
                            .foregroundStyle(AgentsPalette.textSecondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(AgentsText.summary(context.state))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let highlight = context.state.highlight {
                            Text(AgentsText.highlightLine(highlight))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(AgentsPalette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let url = AgentsText.deepLink(context.state) {
                            Link("Abrir", destination: url)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            } compactLeading: {
                AgentsAsterisk(state: context.state)
            } compactTrailing: {
                Text(AgentsText.compactCount(context.state))
                    .monospacedDigit()
                    .foregroundStyle(AgentsAsterisk.color(for: context.state))
            } minimal: {
                AgentsAsterisk(state: context.state)
            }
            .widgetURL(AgentsText.deepLink(context.state))
        }
    }
}

struct AgentsLockScreenView: View {
    let state: MochaAgentsAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentsAsterisk(state: state)
                Text(AgentsText.summary(state))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(AgentsPalette.textPrimary)
                    .lineLimit(1)
            }
            if let highlight = state.highlight {
                HStack {
                    Text(AgentsText.highlightLine(highlight))
                        .lineLimit(1)
                    Spacer()
                    Text(timerInterval: highlight.since...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70, alignment: .trailing)
                }
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(AgentsPalette.textSecondary)
            }
            HStack(spacing: 4) {
                Text("atualizado às \(state.updatedAt.formatted(.dateTime.hour().minute().second())) · há")
                Text(timerInterval: state.updatedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(AgentsPalette.textSecondary)
        }
        .padding()
    }
}

struct AgentsAsterisk: View {
    let state: MochaAgentsAttributes.ContentState

    var body: some View {
        Image(systemName: "asterisk")
            .fontWeight(.bold)
            .foregroundStyle(Self.color(for: state))
    }

    static func color(for state: MochaAgentsAttributes.ContentState) -> Color {
        if state.waiting > 0 { return AgentsPalette.waiting }
        if state.working > 0 { return AgentsPalette.claude }
        return AgentsPalette.textSecondary
    }
}

enum AgentsText {
    static func summary(_ state: MochaAgentsAttributes.ContentState) -> String {
        let parts = [
            state.working > 0 ? "\(state.working) trabalhando" : nil,
            state.waiting > 0 ? "\(state.waiting) esperando você" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "Tudo pronto" : parts.joined(separator: " · ")
    }

    static func compactCount(_ state: MochaAgentsAttributes.ContentState) -> String {
        state.waiting > 0 ? "\(state.waiting)!" : "\(state.working)"
    }

    static func highlightLine(_ highlight: MochaAgentsAttributes.ContentState.Highlight) -> String {
        "\(highlight.title) · \(highlight.workspaceLabel)"
    }

    static func deepLink(_ state: MochaAgentsAttributes.ContentState) -> URL? {
        guard
            let agentId = state.highlight?.agentId,
            let encoded = agentId.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "mocha://agent/" + encoded)
    }
}

enum AgentsPalette {
    static let background = Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255)
    static let textPrimary = Color(red: 0xFC / 255, green: 0xFC / 255, blue: 0xFC / 255)
    static let textSecondary = Color(red: 0x98 / 255, green: 0xA0 / 255, blue: 0xA8 / 255)
    static let claude = Color(red: 0xD8 / 255, green: 0x74 / 255, blue: 0x54 / 255)
    static let waiting = Color(red: 0xF4 / 255, green: 0xB4 / 255, blue: 0x50 / 255)
}
