import MochaClient
import MochaProtocol
import SwiftUI

struct HomeCardSwipeAction {
    let title: String
    let systemImage: String
    let armedColor: Color
    var accessibilityName: String?
    var dismissesCard = false
    let perform: @MainActor () async -> Bool
}

struct HomeCardRow: View {
    let card: HomeCard
    let isOffline: Bool
    let open: () -> Void
    let showDetail: () -> Void
    var leftAction: HomeCardSwipeAction?
    var rightAction: HomeCardSwipeAction?

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
            if offset < 0, let leftAction {
                SwipeActionHint(action: leftAction, isArmed: HomeCardSwipe.revealsAction(offset: offset, width: width))
                    .padding(.trailing, 20)
            }
        }
        .background(alignment: .leading) {
            if offset > 0, let rightAction {
                SwipeActionHint(action: rightAction, isArmed: HomeCardSwipe.revealsAction(offset: offset, width: width))
                    .padding(.leading, 20)
            }
        }
        .onTapGesture(perform: open)
        .onLongPressGesture(perform: showDetail)
        .gesture(
            HorizontalSwipeGesture(
                isEnabled: !swipeDirections.isEmpty && !isOffline,
                directions: swipeDirections,
                onChanged: { offset = HomeCardSwipe.offset(forTranslation: $0, directions: swipeDirections) },
                onEnded: finishSwipe
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: "Ver detalhes", showDetail)
        .accessibilityActions {
            if !isOffline {
                ForEach([leftAction, rightAction].compactMap { $0?.accessibilityName }, id: \.self) { name in
                    Button(name) { performAccessibilityAction(named: name) }
                }
            }
        }
    }

    private var swipeDirections: Set<HomeCardSwipeDirection> {
        var directions: Set<HomeCardSwipeDirection> = []
        if leftAction != nil { directions.insert(.left) }
        if rightAction != nil { directions.insert(.right) }
        return directions
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

    private func action(for direction: HomeCardSwipeDirection) -> HomeCardSwipeAction? {
        switch direction {
        case .left: leftAction
        case .right: rightAction
        }
    }

    private func performAccessibilityAction(named name: String) {
        guard let action = [leftAction, rightAction].compactMap({ $0 }).first(where: { $0.accessibilityName == name }) else { return }
        Task { _ = await action.perform() }
    }

    private func finishSwipe(translation: CGFloat, velocity: CGFloat) {
        guard
            let direction = HomeCardSwipe.triggeredDirection(translation: translation, velocity: velocity, width: width),
            let action = action(for: direction)
        else {
            withAnimation(Self.settleAnimation) { offset = 0 }
            return
        }
        guard action.dismissesCard else {
            withAnimation(Self.settleAnimation) { offset = 0 }
            Task { _ = await action.perform() }
            return
        }
        let distance = width + Self.dismissOvershoot
        withAnimation(Self.settleAnimation) { offset = direction == .left ? -distance : distance }
        Task {
            let dismissed = await action.perform()
            withAnimation(dismissed ? nil : Self.settleAnimation) { offset = 0 }
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
            HomeCardMeta(provider: card.provider, workspace: card.workspace, time: card.time, tone: isOffline ? .offline : .normal)
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

private struct SwipeActionHint: View {
    let action: HomeCardSwipeAction
    let isArmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(action.title)
                .systemText(.cardSubtitle)
        }
        .foregroundStyle(isArmed ? action.armedColor : Palette.textSecondary)
        .animation(.smooth(duration: 0.15), value: isArmed)
        .accessibilityHidden(true)
    }
}
