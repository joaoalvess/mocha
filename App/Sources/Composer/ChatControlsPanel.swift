import MochaClient
import MochaProtocol
import SwiftUI

struct ChatControlsState {
    var agentId: AgentID?
    var sessionId: String?
    var contextLeftPercent: Int?
    var ringStyle: ContextRingStyle = .ready
    var usage: UsageSnapshot?
    var model: ModelAlias?
    var mode: PermissionModeTarget?
    var runningSubagents = 0
    var chatItems: [ChatItem] = []
}

struct ChatControlsPanel: View {
    let session: AppSession
    let state: ChatControlsState
    let maxHeight: CGFloat
    let onMode: (PermissionModeTarget) -> Void
    let onOpenSubagent: (ChatTarget) -> Void
    let onAction: (SlashMenuAction) -> Void
    @State private var subagents: [SubagentSummary] = []
    @State private var contentHeight: CGFloat = 0

    private static let horizontalPadding: CGFloat = 18
    private static let minimumHeight: CGFloat = 120

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: AttachmentLayout.menuWidth, height: visibleHeight, alignment: .top)
        .clipShape(menuShape)
        .background(menuShape.fill(SlashMenuStyle.background))
        .overlay(menuShape.strokeBorder(SlashMenuStyle.border, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controles")
        .task(id: subagentListKey) { await loadSubagents() }
    }

    private var visibleHeight: CGFloat {
        let limit = max(maxHeight, Self.minimumHeight)
        return contentHeight > 0 ? min(contentHeight, limit) : limit
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
                status(now: context.date)
            }
            ControlsSeparator()
            ControlsSegments(
                items: SessionControlChoices.modes.map { choice in
                    ControlsSegmentItem(
                        id: choice.mode.rawValue,
                        title: choice.title,
                        isEnabled: SessionControlChoices.isAvailable(choice.mode, on: state.model)
                    )
                },
                selectedId: state.mode?.rawValue,
                accessibilityLabel: "Modo",
                onSelect: { id in
                    guard let mode = PermissionModeTarget(rawValue: id) else { return }
                    onMode(mode)
                }
            )
            .padding(.horizontal, 10)
            if !SessionControlChoices.isAvailable(.auto, on: state.model) {
                Text("Auto: \(SessionControlChoices.autoUnavailableNote.lowercased())")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 4)
            }
            if let sessionId = state.sessionId, !sessionAgents.isEmpty {
                ControlsSeparator()
                AgentSubagentsSection(items: sessionAgents, sessionId: sessionId, onOpen: onOpenSubagent)
                    .padding(.horizontal, 8)
                    .padding(.top, -14)
            }
            ControlsSeparator()
            ForEach(SlashMenuAction.allCases) { action in
                SlashMenuRow(action: action) { onAction(action) }
            }
        }
        .padding(.vertical, SlashMenuStyle.rowVerticalPadding + 3)
        .frame(width: AttachmentLayout.menuWidth, alignment: .leading)
    }

    private var menuShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AttachmentLayout.menuRadius, style: .continuous)
    }

    private var sessionAgents: [SubagentSummary] {
        SessionAgentsList.merged(subagents: subagents, chatItems: state.chatItems)
    }

    private func status(now: Date) -> some View {
        let windows = state.usage.map { UsagePace.summaries(of: $0, now: now) } ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if let percent = state.contextLeftPercent {
                HStack(spacing: 10) {
                    ContextRing(percent: percent, style: state.ringStyle)
                        .scaleEffect(0.6)
                        .frame(width: 24, height: 24)
                    Text("\(percent)% livre")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text("Contexto")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(height: 30)
                .accessibilityElement(children: .combine)
            }
            ForEach(windows) { window in
                ControlsUsageRow(window: window)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 4)
    }

    private var subagentListKey: ControlsSubagentKey? {
        guard let agentId = state.agentId else { return nil }
        return ControlsSubagentKey(
            agentId: agentId,
            runningSubagents: state.runningSubagents,
            isConnected: session.connectionState == .connected
        )
    }

    private func loadSubagents() async {
        guard let key = subagentListKey, key.isConnected else { return }
        guard
            let reply = try? await session.request(.listSubagents(agentId: key.agentId)),
            case .subagentList(_, let items) = reply
        else { return }
        subagents = items
    }
}

private struct ControlsSubagentKey: Hashable {
    let agentId: AgentID
    let runningSubagents: Int
    let isConnected: Bool
}

private struct ControlsUsageRow: View {
    let window: UsageWindowSummary

    var body: some View {
        HStack(spacing: 10) {
            Text(window.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22, alignment: .leading)
            UsageBar(fraction: window.usedFraction)
            Text(window.percentText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uso de \(window.label)")
        .accessibilityValue(window.percentText)
    }
}

private struct ControlsSeparator: View {
    var body: some View {
        SlashMenuStyle.separator
            .frame(height: 1)
            .padding(.horizontal, SlashMenuStyle.rowPadding)
            .padding(.vertical, SlashMenuStyle.separatorMargin + 2)
            .accessibilityHidden(true)
    }
}

struct ControlsSegmentItem: Identifiable {
    let id: String
    let title: String
    var isEnabled = true
}

struct ControlsSegments: View {
    let items: [ControlsSegmentItem]
    let selectedId: String?
    let accessibilityLabel: String
    let onSelect: (String) -> Void
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button { onSelect(item.id) } label: {
                    Text(item.title)
                        .font(.system(size: titleSize, weight: item.id == selectedId ? .semibold : .regular))
                        .foregroundStyle(item.id == selectedId ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Capsule().fill(item.id == selectedId ? Palette.controlSel : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(!item.isEnabled)
                .opacity(item.isEnabled ? 1 : 0.35)
                .accessibilityAddTraits(item.id == selectedId ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}
