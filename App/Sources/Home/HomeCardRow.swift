import MochaClient
import SwiftUI

struct HomeCardRow: View {
    let card: HomeCard
    let isOffline: Bool
    let open: () -> Void
    let showDetail: () -> Void
    let archive: @MainActor (String) async -> Bool

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0

    private static let settleAnimation = Animation.smooth(duration: 0.22)
    private static let dismissOvershoot: CGFloat = 32

    var body: some View {
        HomeCardFrame(isWarning: card.state == .blocked && !isOffline) {
            ContextRing(percent: card.contextLeftPercent, style: ringStyle)
        } content: {
            HomeCardText(card: card, isOffline: isOffline)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .offset(x: offset)
        .background(alignment: .trailing) {
            if offset < 0 {
                ArchiveSwipeHint(isArmed: HomeCardSwipe.revealsArchiveAction(offset: offset, width: width))
            }
        }
        .onTapGesture(perform: open)
        .onLongPressGesture(perform: showDetail)
        .gesture(
            HorizontalSwipeGesture(
                isEnabled: card.canArchive && !isOffline,
                onChanged: { offset = HomeCardSwipe.offset(forTranslation: $0) },
                onEnded: finishSwipe
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: "Ver detalhes", showDetail)
        .accessibilityActions {
            if let sessionId = card.archiveSessionId, !isOffline {
                Button("Arquivar") {
                    Task { _ = await archive(sessionId) }
                }
            }
        }
    }

    private var ringStyle: ContextRingStyle {
        guard !isOffline else { return .offline }
        switch card.state {
        case .blocked: return .blocked
        case .working: return .working
        case .ready: return .ready
        case .archived: return .archived
        }
    }

    private func finishSwipe(translation: CGFloat, velocity: CGFloat) {
        guard
            let sessionId = card.archiveSessionId,
            HomeCardSwipe.archives(translation: translation, velocity: velocity, width: width)
        else {
            withAnimation(Self.settleAnimation) { offset = 0 }
            return
        }
        withAnimation(Self.settleAnimation) { offset = -(width + Self.dismissOvershoot) }
        Task {
            let archived = await archive(sessionId)
            withAnimation(archived ? nil : Self.settleAnimation) { offset = 0 }
        }
    }
}

private struct HomeCardText: View {
    let card: HomeCard
    let isOffline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeCardTitle(text: card.title, tone: card.state == .archived ? .archived : .normal)
            if let badge = card.subagentBadge {
                HStack(spacing: 0) {
                    SubagentCountBadge(text: badge, tone: isOffline ? .offline : .ok)
                        .padding(.trailing, 7)
                    if let subtitle = card.subtitle {
                        HomeCardSubtitle(text: subtitle, isWarning: card.subtitleIsWarning && !isOffline)
                    }
                }
                .frame(height: 21)
            } else if let subtitle = card.subtitle {
                HomeCardSubtitle(text: subtitle, isWarning: card.subtitleIsWarning && !isOffline)
            }
            HomeCardMeta(workspace: card.workspace, time: card.time, tone: isOffline ? .offline : .normal)
                .padding(.top, hasSecondLine ? 5.5 : 2.5)
        }
    }

    private var hasSecondLine: Bool {
        card.subtitle != nil || card.subagentBadge != nil
    }
}

private struct SubagentCountBadge: View {
    let text: String
    let tone: BadgeTone

    var body: some View {
        HStack(spacing: 4) {
            LineIconView(icon: .agent, size: 11, strokeWidth: 2.2, color: tone.foreground)
            Text(text)
                .systemText(.badge)
                .foregroundStyle(tone.foreground)
                .lineLimit(1)
        }
        .padding(.leading, 5.5)
        .padding(.trailing, 7)
        .frame(height: 17.3)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tone.background))
        .fixedSize()
    }
}

private struct ArchiveSwipeHint: View {
    let isArmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "archivebox")
                .font(.system(size: 15, weight: .semibold))
            Text("Arquivar")
                .systemText(.cardSubtitle)
        }
        .foregroundStyle(isArmed ? Palette.statusOk : Palette.textSecondary)
        .padding(.trailing, 20)
        .animation(.smooth(duration: 0.15), value: isArmed)
        .accessibilityHidden(true)
    }
}
