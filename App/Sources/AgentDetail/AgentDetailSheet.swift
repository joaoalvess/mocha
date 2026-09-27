import MochaClient
import MochaProtocol
import SwiftUI
import UIKit

struct AgentDetailSheet: View {
    @Bindable var session: AppSession
    let target: ChatTarget
    @State private var subagents: [SubagentSummary] = []

    private static let contentTop: CGFloat = 4
    private static let closeInset: CGFloat = 16

    var body: some View {
        TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
            ScrollView {
                AgentDetailContent(
                    info: AgentDetailInfo(session: session, target: target),
                    hostName: session.host?.hostName,
                    usage: session.usage,
                    now: context.date,
                    subagents: subagents,
                    onOpenSubagent: { session.openChat($0) }
                )
                .padding(.horizontal, Metrics.contentMargin)
                .padding(.top, Self.contentTop)
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topLeading) {
            GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .hero) {
                session.dismissSheet()
            }
            .padding(.leading, Self.closeInset)
            .padding(.top, Self.closeInset)
        }
        .task(id: subagentListKey) { await loadSubagents() }
    }

    private var subagentListKey: SubagentListKey? {
        guard case .agent(let agentId) = target else { return nil }
        return SubagentListKey(
            agentId: agentId,
            runningSubagents: session.workspaces.agent(withId: agentId)?.runningSubagents ?? 0,
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

private struct SubagentListKey: Hashable {
    let agentId: AgentID
    let runningSubagents: Int
    let isConnected: Bool
}

struct AgentDetailInfo {
    var title: String
    var workspace: String
    var activityAt: Date?
    var badge: StateBadgeStyle
    var model: String?
    var tabTitle: String?
    var sessionId: String?
    var isAgent = false

    @MainActor
    init(session: AppSession, target: ChatTarget) {
        switch target {
        case .agent(let agentId):
            let agent = session.workspaces.agent(withId: agentId)
            title = HomeSections.title(for: agent?.preview)
            workspace = agent?.workspaceLabel ?? Self.missing
            activityAt = agent?.lastActivityAt
            badge = Self.badge(for: agent?.status ?? .unknown)
            model = agent?.model
            tabTitle = session.workspaces.tab(containingAgent: agentId)?.title
            sessionId = agent?.sessionId
            isAgent = true
        case .session(let sessionId):
            let archived = session.archivedSessions.first { $0.id == sessionId }
            title = HomeSections.title(for: archived?.preview)
            workspace = archived?.workspaceLabel ?? Self.missing
            activityAt = archived.map { $0.lastActivityAt ?? $0.endedAt }
            badge = .ended
            model = archived?.model
            tabTitle = archived?.agentId.flatMap { session.workspaces.tab(containingAgent: $0)?.title }
            self.sessionId = sessionId
        case .subagent:
            title = HomeSections.title(for: nil)
            workspace = Self.missing
            activityAt = nil
            badge = Self.badge(for: .unknown)
            model = nil
            tabTitle = nil
            sessionId = nil
        }
    }

    static let missing = "—"

    static func badge(for status: AgentStatus) -> StateBadgeStyle {
        switch status {
        case .blocked: .needsYou
        case .working: .working
        case .idle, .done, .unknown: .ready
        }
    }
}

private struct AgentDetailContent: View {
    let info: AgentDetailInfo
    let hostName: String?
    let usage: UsageSnapshot?
    let now: Date
    let subagents: [SubagentSummary]
    let onOpenSubagent: (ChatTarget) -> Void

    var body: some View {
        VStack(spacing: 0) {
            AgentDetailHero(info: info, hostName: hostName, now: now)
            if info.isAgent, let sessionId = info.sessionId, !subagents.isEmpty {
                AgentSubagentsSection(items: subagents, sessionId: sessionId, onOpen: onOpenSubagent)
            }
            if let usage {
                let windows = UsagePace.summaries(of: usage, now: now)
                if !windows.isEmpty {
                    AccountCard(title: UsagePace.accountTitle(plan: usage.plan, account: usage.account), windows: windows)
                        .padding(.top, 20.3)
                }
            }
            AgentDetailList(info: info, hostName: hostName)
                .padding(.top, 16.3)
        }
    }
}

private struct AgentDetailHero: View {
    let info: AgentDetailInfo
    let hostName: String?
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ClaudeTile(size: 80, cornerRadius: 22, background: Palette.heroTile, markSize: 48)
            Text(info.title)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.35)
                .lineHeight(.exact(points: 28))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16.7)
            meta
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 7.9)
            StateBadge(style: info.badge)
                .padding(.top, 15.4)
        }
        .padding(.horizontal, 26)
        .padding(.top, 23.7)
        .padding(.bottom, 24.3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.heroBg))
    }

    private var meta: Text {
        let workspace = Text(info.workspace)
            .font(Typography.mono(15))
            .tracking(-0.2)
            .foregroundStyle(info.badge == .needsYou ? Palette.dirty : Palette.statusOk)
        let details = [hostName, info.activityAt.map { RelativeTime.text(from: $0, now: now) }].compactMap { $0 }
        guard !details.isEmpty else { return workspace }
        return Text("\(workspace) · \(details.joined(separator: " · "))")
    }
}

private struct AccountCard: View {
    let title: String
    let windows: [UsageWindowSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 3.7) {
            HStack {
                Text("Conta")
                Spacer(minLength: 12)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 14))
            .systemLinePitch(20, size: 14)
            .foregroundStyle(Palette.textSecondary)
            VStack(spacing: 0) {
                ForEach(windows) { window in
                    AccountWindowRow(window: window)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .padding(.leading, 16.3)
        .padding(.trailing, 16.7)
        .frame(minHeight: 91.7, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.toolCard))
        .accessibilityElement(children: .combine)
    }
}

private struct AccountWindowRow: View {
    let window: UsageWindowSummary

    var body: some View {
        HStack(spacing: 0) {
            Text(window.label)
                .font(Typography.usageLabel)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 63.7, alignment: .leading)
            UsageBar(fraction: window.usedFraction)
                .frame(width: 141.7)
            Text(window.percentText)
                .font(Typography.usageValue)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 48.3, alignment: .trailing)
            Text(window.timeUntilReset ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

private struct AgentDetailList: View {
    let info: AgentDetailInfo
    let hostName: String?

    @State private var isCopied = false

    private static let copiedDuration: Duration = .seconds(1.5)

    var body: some View {
        SheetListCard {
            SheetListRow(label: "Host", value: hostName ?? AgentDetailInfo.missing, isCompact: true)
            SheetListRow(label: "Modelo", value: info.model.map(ModelName.abbreviated) ?? AgentDetailInfo.missing, isCompact: true)
            SheetListRow(label: "Workspace do Herdr", value: info.workspace, valueStyle: .mono, isCompact: true)
            SheetListRow(label: "Tab do Herdr", value: info.tabTitle ?? AgentDetailInfo.missing, valueStyle: .mono, isCompact: true)
            sessionRow
        }
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: Self.copiedDuration)
            isCopied = false
        }
    }

    @ViewBuilder
    private var sessionRow: some View {
        if let sessionId = info.sessionId {
            SheetListRow(
                label: "Sessão",
                value: isCopied ? "Copiado" : SessionIdFormat.shortened(sessionId),
                valueStyle: .mono,
                isCompact: true
            ) {
                LineIconView(
                    icon: isCopied ? .check : .copy,
                    size: 16,
                    strokeWidth: 1.8,
                    color: isCopied ? Palette.statusOk : Palette.textSecondary
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { copy(sessionId) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copia o id da sessão")
        } else {
            SheetListRow(label: "Sessão", value: AgentDetailInfo.missing, valueStyle: .mono, isCompact: true)
        }
    }

    private func copy(_ sessionId: String) {
        UIPasteboard.general.string = sessionId
        isCopied = true
    }
}
