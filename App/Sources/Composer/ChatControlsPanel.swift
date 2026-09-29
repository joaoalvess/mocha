import MochaClient
import MochaProtocol
import SwiftUI

struct ChatControlsState {
    var agentId: AgentID?
    var sessionId: String?
    var contextLeftPercent: Int?
    var contextUsedTokens: Int?
    var ringStyle: ContextRingStyle = .ready
    var usage: UsageSnapshot?
    var model: ModelAlias?
    var mode: PermissionModeTarget?
    var runningSubagents = 0
    var chatItems: [ChatItem] = []
}

enum ControlsPage: String {
    case root
    case mode
    case usage
    case subagents

    var title: String {
        switch self {
        case .root: "Controles"
        case .mode: "Modo"
        case .usage: "Uso"
        case .subagents: "Subagentes"
        }
    }
}

enum ControlsPanelStyle {
    static let secondary = Color(hex: 0xB4BAC1)
    static let border = Color(hex: 0xFFFFFF, opacity: 0.14)
    static let navRowHeight: CGFloat = 42
    static let contextRowHeight: CGFloat = 38
    static let headerHeight: CGFloat = 46
    static let listRowHeight: CGFloat = 54
    static let verticalPadding: CGFloat = 6
    static let navigation = Animation.easeOut(duration: 0.3)
    static let pageKey = "chat-controls-page"
}

struct ChatControlsPanel: View {
    let session: AppSession
    let state: ChatControlsState
    let maxHeight: CGFloat
    let onMode: (PermissionModeTarget) -> Void
    let onOpenSubagent: (ChatTarget) -> Void
    let onAction: (SlashMenuAction) -> Void
    @State private var subagents: [SubagentSummary] = []
    @State private var page: ControlsPage = .root
    @State private var detailPage: ControlsPage?
    @State private var heights: [ControlsPage: CGFloat] = [:]

    private static let minimumHeight: CGFloat = 120
    private static let width = AttachmentLayout.menuWidth

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageContainer(.root) { rootContent }
                .offset(x: page == .root ? 0 : -Self.width)
                .allowsHitTesting(page == .root)
                .accessibilityHidden(page != .root)
            if let detailPage {
                pageContainer(detailPage) { detailContent(detailPage) }
                    .offset(x: page == .root ? Self.width : 0)
                    .allowsHitTesting(page != .root)
                    .accessibilityHidden(page == .root)
            }
        }
        .frame(width: Self.width, height: visibleHeight(for: page), alignment: .topLeading)
        .clipShape(menuShape)
        .mochaGlass(.composer, in: menuShape)
        .overlay(menuShape.strokeBorder(ControlsPanelStyle.border, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controles")
        .task(id: subagentListKey) { await loadSubagents() }
        .onAppear(perform: openPageForDebugLaunch)
    }

    private var menuShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AttachmentLayout.menuRadius, style: .continuous)
    }

    private var limit: CGFloat {
        max(maxHeight, Self.minimumHeight)
    }

    private func visibleHeight(for page: ControlsPage) -> CGFloat {
        guard let height = heights[page], height > 0 else { return limit }
        return min(height, limit)
    }

    private func pageContainer(_ page: ControlsPage, @ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            content()
                .padding(.vertical, ControlsPanelStyle.verticalPadding)
                .frame(width: Self.width, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[page] = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width, height: visibleHeight(for: page), alignment: .top)
    }

    private var sessionAgents: [SubagentSummary] {
        guard state.sessionId != nil else { return [] }
        return SessionAgentsList.merged(subagents: subagents, chatItems: state.chatItems)
    }

    private func summary(now: Date) -> ControlsPanelSummary {
        ControlsPanelSummary(
            contextLeftPercent: state.contextLeftPercent,
            contextUsedTokens: state.contextUsedTokens,
            mode: state.mode,
            usage: usageWindows(now: now),
            subagents: sessionAgents
        )
    }

    private func usageWindows(now: Date) -> [UsageWindowSummary] {
        state.usage.map { UsagePace.summaries(of: $0, now: now) } ?? []
    }

    private var rootContent: some View {
        TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
            let summary = summary(now: context.date)
            VStack(alignment: .leading, spacing: 0) {
                if let percent = state.contextLeftPercent, let text = summary.contextText {
                    ControlsContextRow(percent: ControlsPanelSummary.contextUsedPercent(leftPercent: percent), text: text, style: state.ringStyle)
                    ControlsSeparator()
                }
                ControlsNavRow(icon: .mode, title: "Modo", value: summary.modeText) { open(.mode) }
                if let usage = summary.usageText {
                    ControlsNavRow(icon: .usage, title: "Uso", value: usage) { open(.usage) }
                }
                if let subagentsText = summary.subagentsText {
                    ControlsNavRow(icon: .subagents, title: "Subagentes", value: subagentsText) { open(.subagents) }
                }
                ControlsSeparator()
                ForEach(SlashMenuAction.allCases) { action in
                    SlashMenuRow(action: action) { onAction(action) }
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ page: ControlsPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlsBackHeader(title: page.title) { back() }
            switch page {
            case .root:
                EmptyView()
            case .mode:
                modeList
            case .usage:
                TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
                    ControlsUsageList(windows: usageWindows(now: context.date))
                }
            case .subagents:
                if let sessionId = state.sessionId {
                    ControlsSubagentList(items: sessionAgents, sessionId: sessionId, onOpen: onOpenSubagent)
                }
            }
        }
    }

    private var modeList: some View {
        VStack(spacing: 0) {
            ForEach(SessionControlChoices.modes) { choice in
                ControlsModeRow(
                    choice: choice,
                    isSelected: choice.mode == state.mode,
                    isEnabled: SessionControlChoices.isAvailable(choice.mode, on: state.model)
                ) {
                    onMode(choice.mode)
                    back()
                }
            }
        }
    }

    private func open(_ destination: ControlsPage) {
        detailPage = destination
        withAnimation(ControlsPanelStyle.navigation) { page = destination }
    }

    private func back() {
        withAnimation(ControlsPanelStyle.navigation) { page = .root }
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

    private func openPageForDebugLaunch() {
        #if DEBUG
        guard
            let raw = LaunchArguments.argumentDomain()[ControlsPanelStyle.pageKey] as? String,
            let debugPage = ControlsPage(rawValue: raw),
            debugPage != .root,
            ChatDebugLaunch.consume(ControlsPanelStyle.pageKey)
        else { return }
        detailPage = debugPage
        page = debugPage
        #endif
    }
}

private struct ControlsSubagentKey: Hashable {
    let agentId: AgentID
    let runningSubagents: Int
    let isConnected: Bool
}

private extension ContextRingStyle {
    var barColor: Color {
        switch self {
        case .ready, .working: Palette.statusOk
        case .blocked: Palette.dirty
        case .archived: Palette.statusOk.opacity(0.28)
        case .offline: Palette.offlineRing
        }
    }
}

private struct ControlsContextRow: View {
    let percent: Int
    let text: String
    let style: ContextRingStyle

    var body: some View {
        HStack(spacing: 12) {
            Text("Contexto")
                .font(.system(size: 15))
                .foregroundStyle(ControlsPanelStyle.secondary)
                .fixedSize()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.barTrack)
                    Capsule()
                        .fill(style.barColor)
                        .frame(width: max(4, proxy.size.width * CGFloat(min(max(percent, 0), 100)) / 100))
                }
            }
            .frame(height: 4)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .fixedSize()
        }
        .padding(.horizontal, SlashMenuStyle.rowPadding)
        .frame(height: ControlsPanelStyle.contextRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Contexto")
        .accessibilityValue(text)
    }
}

private struct ControlsNavRow: View {
    let icon: SlashMenuIcon
    let title: String
    let value: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SlashMenuStyle.rowSpacing) {
                SlashMenuIconView(icon: icon, size: SlashMenuStyle.iconSize, strokeWidth: SlashMenuStyle.iconStrokeWidth, color: Palette.textPrimary)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(ControlsPanelStyle.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.3, color: ControlsPanelStyle.secondary)
                }
            }
            .padding(.horizontal, SlashMenuStyle.rowPadding)
            .frame(height: ControlsPanelStyle.navRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct ControlsBackHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 8) {
                SlashMenuIconView(icon: .chevronLeft, size: 16, strokeWidth: 2.4, color: Palette.textPrimary)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: ControlsPanelStyle.headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Voltar")
        .accessibilityValue(title)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ControlsModeRow: View {
    let choice: ModeChoice
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SlashMenuStyle.rowSpacing) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(ControlsPanelStyle.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    LineIconView(icon: .check, size: 16, strokeWidth: 2.2, color: Palette.statusOk)
                }
            }
            .padding(.horizontal, SlashMenuStyle.rowPadding)
            .frame(height: ControlsPanelStyle.listRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("\(choice.title), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detail: String {
        isEnabled ? choice.detail : SessionControlChoices.autoUnavailableNote.lowercased()
    }

    @ViewBuilder
    private var icon: some View {
        switch choice.mode {
        case .acceptEdits, .default:
            LineIconView(icon: .pencil, size: SlashMenuStyle.iconSize, strokeWidth: SlashMenuStyle.iconStrokeWidth, color: Palette.textPrimary)
        case .auto:
            LineIconView(icon: .sparkles, size: SlashMenuStyle.iconSize, strokeWidth: SlashMenuStyle.iconStrokeWidth, color: Palette.textPrimary)
        case .plan:
            SlashMenuIconView(icon: .plan, size: SlashMenuStyle.iconSize, strokeWidth: SlashMenuStyle.iconStrokeWidth, color: Palette.textPrimary)
        }
    }
}

private struct ControlsUsageList: View {
    let windows: [UsageWindowSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ControlsPanelSummary.usageTitle(window))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 8)
                        Text(window.percentText)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    UsageBar(fraction: window.usedFraction, paceFraction: window.elapsedFraction)
                    if let reset = ControlsPanelSummary.resetText(window) {
                        Text(reset)
                            .font(.system(size: 13))
                            .foregroundStyle(ControlsPanelStyle.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ControlsPanelSummary.usageTitle(window))
                .accessibilityValue([window.percentText + " usado", ControlsPanelSummary.resetText(window)].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .padding(.horizontal, SlashMenuStyle.rowPadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct ControlsSubagentList: View {
    let items: [SubagentSummary]
    let sessionId: String
    let onOpen: (ChatTarget) -> Void

    var body: some View {
        if SubagentRows.hasRunning(items) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                list(now: context.date)
            }
        } else {
            list(now: Date())
        }
    }

    private func list(now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onOpen(.subagent(sessionId: sessionId, agentId: item.agentId))
                } label: {
                    HStack(spacing: 12) {
                        SubagentStateIcon(status: item.status, size: 16)
                            .frame(width: SlashMenuStyle.iconSize)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.description)
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.textPrimary)
                            Text(ControlsPanelSummary.subagentDetail(item, now: now))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(ControlsPanelStyle.secondary)
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.3, color: ControlsPanelStyle.secondary)
                    }
                    .padding(.horizontal, SlashMenuStyle.rowPadding)
                    .frame(height: ControlsPanelStyle.listRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Abre o transcript do subagente")
            }
        }
    }
}

private struct ControlsSeparator: View {
    var body: some View {
        SlashMenuStyle.separator
            .frame(height: 1)
            .padding(.horizontal, SlashMenuStyle.rowPadding)
            .padding(.vertical, 3)
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
