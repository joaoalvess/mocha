import MochaClient
import MochaProtocol
import SwiftUI

struct HistoryScreen: View {
    @Bindable var session: AppSession
    @State private var offlineProblem: ConnectionProblem?

    var body: some View {
        TimelineView(.periodic(from: .now, by: HomeSections.refreshInterval)) { context in
            HomeContent(session: session, now: context.date, offlineMessage: offlineProblem?.message)
        }
        .onChange(of: session.connectionState, initial: true) { _, state in
            offlineProblem = HomeSections.offlineProblem(for: state, previous: offlineProblem)
        }
        .task { await runDebugLaunch() }
    }

    private func runDebugLaunch() async {
        #if DEBUG
        guard let agentId = HomeDebugOptions.current().openDetailAgentId else { return }
        while session.workspaces.agent(withId: agentId) == nil {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if HomeDebugLaunch.consume(HomeDebugOptions.openDetailKey) {
            session.showDetail(.agent(agentId))
        }
        #endif
    }
}

private struct HomeContent: View {
    @Bindable var session: AppSession
    let now: Date
    let offlineMessage: String?

    private static let pillSide: CGFloat = 22
    private static let pillBottom: CGFloat = 9
    private static let listBottomWithPill: CGFloat = 64
    private static let listBottom: CGFloat = 24
    private static let capsuleTopInset: CGFloat = 11
    private static let capsuleSideInset: CGFloat = 52

    var body: some View {
        let sections = HomeSections.make(agents: session.workspaces.allAgents, archived: session.archivedSessions, now: now)
        let usageWindows = session.usage.map { UsagePace.summaries(of: $0, now: now) } ?? []
        ZStack(alignment: .top) {
            HomeBackground()
            if !sections.isEmpty {
                HomeList(
                    session: session,
                    sections: sections,
                    isOffline: offlineMessage != nil,
                    bottomInset: usageWindows.isEmpty ? Self.listBottom : Self.listBottomWithPill
                )
            } else if session.hasReceivedTree {
                HomeEmptyState()
            }
            topBar
        }
        .overlay(alignment: .bottom) {
            if !usageWindows.isEmpty {
                HomeUsagePill(provider: session.usage?.provider ?? .claude, windows: usageWindows, isDimmed: offlineMessage != nil) {
                    session.showUsage()
                }
                .padding(.horizontal, Self.pillSide)
                .padding(.bottom, Self.pillBottom)
            }
        }
    }

    private var topBar: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                GlassRoundButton(systemImage: "house", accessibilityLabel: "Início", style: .home) {
                    session.showStart()
                }
                Spacer()
                GlassRoundButton(systemImage: "gearshape", accessibilityLabel: "Ajustes", style: .home) {
                    session.showSettings()
                }
            }
            if let offlineMessage {
                OfflineCapsule(message: offlineMessage) { session.showSettings() }
                    .padding(.horizontal, Self.capsuleSideInset)
                    .padding(.top, Self.capsuleTopInset)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Metrics.homeButtonSide)
        .padding(.top, Metrics.homeButtonTopInset)
        .animation(.smooth(duration: 0.25), value: offlineMessage)
    }
}

private struct HomeList: View {
    let session: AppSession
    let sections: [HomeSection]
    let isOffline: Bool
    let bottomInset: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    SectionHeader(
                        title: section.kind.title,
                        topPadding: index == 0 ? SectionHeaderSpacing.first : Metrics.sectionHeaderTopAfterCard
                    )
                    ForEach(section.cards) { card in
                        HomeCardRow(
                            card: card,
                            isOffline: isOffline,
                            open: { session.openChat(card.target) },
                            showDetail: { session.showDetail(card.target) },
                            archive: archive
                        )
                        .padding(.horizontal, Metrics.contentMargin)
                        .padding(.bottom, Metrics.homeCardSpacing)
                    }
                }
            }
            .padding(.top, Metrics.homeListTopInset)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .animation(.smooth(duration: 0.3), value: sections)
    }

    private func archive(_ sessionId: String, provider: AgentProvider) async -> Bool {
        do {
            try await session.archive(sessionId: sessionId, provider: provider)
            return true
        } catch {
            return false
        }
    }
}

private enum SectionHeaderSpacing {
    static let first: CGFloat = 12
}
