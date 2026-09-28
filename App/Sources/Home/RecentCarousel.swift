import MochaClient
import MochaProtocol
import SwiftUI

struct RecentCarousel: View {
    let items: [RecentItem]
    let isOffline: Bool
    let open: (ChatTarget) -> Void
    let showDetail: (ChatTarget) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    RecentCard(item: item, isOffline: isOffline)
                        .onTapGesture { open(item.card.target) }
                        .onLongPressGesture { showDetail(item.card.target) }
                }
            }
            .padding(.horizontal, Metrics.contentMargin)
        }
        .scrollIndicators(.hidden)
    }
}

private struct RecentCard: View {
    let item: RecentItem
    let isOffline: Bool

    static let side: CGFloat = 162

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecentThumbnailView(item: item, isOffline: isOffline)
            Text(item.card.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(height: 20)
                .padding(.top, 8)
            HStack(spacing: 5) {
                Text(item.card.workspace)
                    .font(Typography.mono(12.5, .regular))
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.statusOk)
                Text(verbatim: "·")
                Text(item.card.time)
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .frame(height: 17)
            .padding(.top, 1)
        }
        .frame(width: Self.side, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.stateText)
        .accessibilityAddTraits(.isButton)
    }
}

private struct RecentThumbnailView: View {
    let item: RecentItem
    let isOffline: Bool

    private static let font = Typography.mono(9.5)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack(alignment: .topLeading) {
            conversation
                .opacity(item.card.state == .archived ? 0.55 : 1)
                .padding(.horizontal, 10)
                .padding(.top, 38)
            LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 46)
                .frame(maxHeight: .infinity, alignment: .bottom)
            HStack {
                stateChip
                Spacer()
                providerChip
            }
            .padding(8)
        }
        .frame(width: RecentCard.side, height: RecentCard.side, alignment: .topLeading)
        .background(shape.fill(Palette.bg))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let userText = item.thumbnail.userText {
                Text(userText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.userBubble))
                    .frame(maxWidth: 142 * 0.88, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 7)
            }
            if let toolName = item.thumbnail.toolName {
                HStack(spacing: 4) {
                    Text(toolName)
                        .font(Typography.mono(9.5, .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(item.thumbnail.toolSummary ?? "")
                        .foregroundStyle(Palette.textSecondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                .background(Capsule().fill(Palette.toolCard))
                .padding(.bottom, 6)
            }
            if let assistantText = item.thumbnail.assistantText {
                Text(assistantText)
            }
        }
        .font(Self.font)
        .lineSpacing(13 - 9.5 * Typography.monoLineHeightRatio)
        .foregroundStyle(Palette.textPrimary)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var stateChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: item.card.state == .working && !isOffline ? Palette.statusOk.opacity(0.8) : .clear, radius: 3)
            Text(item.stateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(Capsule().fill(Palette.toolCard.opacity(0.86)))
    }

    private var providerChip: some View {
        ProviderMark(provider: item.card.provider, size: 13)
            .foregroundStyle(Color(hex: 0xE8E8EA))
            .frame(width: 22, height: 22)
            .background(Circle().fill(Palette.toolCard.opacity(0.86)))
    }

    private var dotColor: Color {
        if isOffline { return Palette.textSecondary }
        switch item.card.state {
        case .blocked: return Palette.dirty
        case .working, .ready: return Palette.statusOk
        case .archived: return Palette.textSecondary
        }
    }
}
