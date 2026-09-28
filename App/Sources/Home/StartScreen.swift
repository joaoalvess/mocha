import MochaClient
import MochaProtocol
import SwiftUI

struct StartScreen: View {
    @Bindable var session: AppSession
    @State private var offlineProblem: ConnectionProblem?

    var body: some View {
        TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
            StartContent(session: session, now: context.date, offlineMessage: offlineProblem?.message)
        }
        .onChange(of: session.connectionState, initial: true) { _, state in
            offlineProblem = HomeSections.offlineProblem(for: state, previous: offlineProblem)
        }
    }
}

private struct StartContent: View {
    @Bindable var session: AppSession
    let now: Date
    let offlineMessage: String?

    private static let searchTop: CGFloat = 60
    private static let searchHeight: CGFloat = 46
    private static let listTop: CGFloat = 118
    private static let offlineGap: CGFloat = 10
    private static let offlineHeight: CGFloat = 34
    private static let activeTopGap: CGFloat = 22
    private static let listBottom: CGFloat = 110
    private static let fabTrailing: CGFloat = 20
    private static let fabBottom: CGFloat = 6
    private static let headerButtonSpacing: CGFloat = 8

    var body: some View {
        let sections = HomeSections.make(agents: session.workspaces.allAgents, archived: session.archivedSessions, now: now)
        let active = StartSections.active(sections)
        let recents = StartSections.recents(agents: session.workspaces.allAgents, archived: session.archivedSessions, now: now)
        ZStack(alignment: .top) {
            HomeBackground()
            if !recents.isEmpty || !active.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !recents.isEmpty {
                            RecentsHeader()
                            RecentCarousel(items: recents, isOffline: offlineMessage != nil, open: open, showDetail: showDetail)
                        }
                        ForEach(Array(active.enumerated()), id: \.element.id) { index, section in
                            SectionHeader(
                                title: section.kind.title,
                                topPadding: index == 0 ? Self.activeTopGap : Metrics.sectionHeaderTopAfterCard
                            )
                            ForEach(section.cards) { card in
                                HomeCardRow(
                                    card: card,
                                    isOffline: offlineMessage != nil,
                                    open: { open(card.target) },
                                    showDetail: { showDetail(card.target) },
                                    archive: { _, _ in false }
                                )
                                .padding(.horizontal, Metrics.contentMargin)
                                .padding(.bottom, Metrics.homeCardSpacing)
                            }
                        }
                    }
                    .padding(.top, listTop)
                    .padding(.bottom, Self.listBottom)
                    .animation(.smooth(duration: 0.3), value: active)
                }
                .scrollIndicators(.hidden)
            } else if session.hasReceivedTree {
                StartEmptyState()
            }
            topBar
        }
        .overlay(alignment: .bottomTrailing) {
            NewSessionButton { session.showNewSession() }
                .padding(.trailing, Self.fabTrailing)
                .padding(.bottom, Self.fabBottom)
        }
    }

    private var listTop: CGFloat {
        Self.listTop + (offlineMessage == nil ? 0 : Self.offlineHeight + Self.offlineGap)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AgentRingsButton(
                    counts: AgentRingCounts(statuses: session.supportedAgents.map(\.status)),
                    isOffline: offlineMessage != nil
                ) {
                    session.showHistory()
                }
                Spacer()
                HStack(spacing: Self.headerButtonSpacing) {
                    if session.pending.count > 0 {
                        HomeInboxButton(pendingCount: session.pending.count) { session.showInbox() }
                            .transition(.scale.combined(with: .opacity))
                    }
                    GlassRoundButton(systemImage: "gearshape", accessibilityLabel: "Ajustes", style: .home) {
                        session.showSettings()
                    }
                }
                .animation(.smooth(duration: 0.25), value: session.pending.count > 0)
            }
            StartSearchField()
                .padding(.top, Self.searchTop - GlassRoundButtonStyle.home.diameter)
            if let offlineMessage {
                OfflineCapsule(message: offlineMessage) { session.showSettings() }
                    .padding(.top, Self.offlineGap)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Metrics.homeButtonSide)
        .padding(.top, Metrics.homeButtonTopInset)
        .animation(.smooth(duration: 0.25), value: offlineMessage)
    }

    private func open(_ target: ChatTarget) {
        session.openChat(target)
    }

    private func showDetail(_ target: ChatTarget) {
        session.showDetail(target)
    }
}

private struct RecentsHeader: View {
    var body: some View {
        HStack {
            Text("RECENTES")
                .systemText(.sectionHeader)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("Segure para opções")
                .font(.system(size: 12))
                .foregroundStyle(Palette.usageFootnote)
        }
        .frame(height: 16)
        .padding(.horizontal, Metrics.contentMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct HomeInboxButton: View {
    let pendingCount: Int
    let action: () -> Void

    var body: some View {
        GlassRoundButton(systemImage: "bell", accessibilityLabel: "Pedidos pendentes", style: .home, action: action)
            .overlay(alignment: .topTrailing) { badge }
            .accessibilityValue("\(pendingCount)")
    }

    @ViewBuilder
    private var badge: some View {
        if let text = PendingText.badge(pendingCount) {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.glyphOnDirty)
                .padding(.horizontal, 4)
                .frame(minWidth: 17, minHeight: 17)
                .background(Capsule().fill(Palette.dirty))
                .offset(x: 3, y: -3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct StartSearchField: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
            Text("Buscar")
                .font(.system(size: 17))
            Spacer()
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background {
            Capsule()
                .fill(Color(hex: 0x15171A))
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Buscar")
    }
}

private struct NewSessionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(hex: 0x021402))
                .frame(width: 60, height: 60)
                .background(Circle().fill(Palette.statusOk))
                .shadow(color: Palette.statusOk.opacity(0.18), radius: 15, y: 10)
                .shadow(color: .black.opacity(0.5), radius: 11, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Nova sessão")
    }
}

private struct StartEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Nenhum agente aberto no Herdr")
                .font(.system(size: 19, weight: .semibold))
                .systemLinePitch(24, size: 19)
                .foregroundStyle(Palette.textPrimary)
            Text("Toque em + para abrir uma tab com Claude ou Codex num workspace.")
                .font(.system(size: 15))
                .systemLinePitch(21, size: 15)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.top, 325)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
