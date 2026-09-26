import SwiftUI

enum BubbleDelivery: Equatable {
    case delivered
    case sending
    case unconfirmed
}

struct UserBubble: View {
    let text: String
    var delivery: BubbleDelivery = .delivered

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            TrailingBubbleLayout(maxWidthFraction: 0.85) {
                Text(text)
                    .chatBodyStyle()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .circular)
                            .fill(Palette.userBubble)
                    )
            }
            .opacity(delivery == .delivered ? 1 : 0.5)
            if let label = deliveryLabel {
                HStack(spacing: 5) {
                    Image(systemName: delivery == .sending ? "clock" : "exclamationmark.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text(label)
                        .font(Typography.pendingLabel)
                }
                .foregroundStyle(Palette.textSecondary)
                .frame(height: 14)
                .padding(.trailing, 3)
            }
        }
    }

    private var deliveryLabel: String? {
        switch delivery {
        case .delivered: nil
        case .sending: "enviando…"
        case .unconfirmed: "sem confirmação"
        }
    }
}

struct TrailingBubbleLayout: Layout {
    var maxWidthFraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = bubbleSize(available: proposal.width, subview: subview)
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let size = bubbleSize(available: bounds.width, subview: subview)
        subview.place(
            at: CGPoint(x: bounds.maxX - size.width, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }

    private func bubbleSize(available: CGFloat?, subview: LayoutSubview) -> CGSize {
        let idealSize = subview.sizeThatFits(.unspecified)
        guard let available, available.isFinite else { return idealSize }
        let width = min(idealSize.width, available * maxWidthFraction)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

struct SlashChip: View {
    let command: String

    var body: some View {
        Text(command)
            .font(Typography.slashChip)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(Palette.toolCard))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
