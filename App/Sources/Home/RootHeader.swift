import MochaClient
import SwiftUI

struct RootHeader: View {
    let session: AppSession
    let historyProgress: CGFloat
    let offlineMessage: String?

    static let offlineGap: CGFloat = 10
    static let offlineHeight: CGFloat = 34
    static let offlineExtent: CGFloat = offlineGap + offlineHeight

    private static let buttonSpacing: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RootPageButton(
                    counts: AgentRingCounts(statuses: session.supportedAgents.map(\.status)),
                    isOffline: offlineMessage != nil,
                    historyProgress: historyProgress,
                    action: togglePage
                )
                Spacer()
                HStack(spacing: Self.buttonSpacing) {
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

    private func togglePage() {
        switch session.rootPage {
        case .start: session.showHistory()
        case .history: session.showStart()
        }
    }
}

private struct RootPageButton: View {
    let counts: AgentRingCounts
    let isOffline: Bool
    let historyProgress: CGFloat
    let action: () -> Void

    private static let style = GlassRoundButtonStyle.home
    private static let hiddenScale: CGFloat = 0.6

    var body: some View {
        Button(action: action) {
            ZStack {
                AgentRings(counts: counts, isOffline: isOffline)
                    .opacity(1 - historyProgress)
                    .scaleEffect(scale(visibility: 1 - historyProgress))
                Image(systemName: "house")
                    .font(.system(size: Self.style.iconSize * 0.9))
                    .foregroundStyle(Palette.textPrimary)
                    .opacity(historyProgress)
                    .scaleEffect(scale(visibility: historyProgress))
            }
            .frame(width: Self.style.diameter, height: Self.style.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .mochaGlass(Self.style.tint, interactive: true, in: Circle())
        .accessibilityLabel(showsHome ? "Início" : "Histórico")
        .accessibilityValue(showsHome ? "" : counts.accessibilityValue)
    }

    private var showsHome: Bool {
        historyProgress > 0.5
    }

    private func scale(visibility: CGFloat) -> CGFloat {
        Self.hiddenScale + (1 - Self.hiddenScale) * visibility
    }
}

private struct HomeInboxButton: View {
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
