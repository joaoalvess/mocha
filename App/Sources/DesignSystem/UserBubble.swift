import SwiftUI

struct UserBubble: View {
    let text: String

    var body: some View {
        TrailingBubbleLayout(maxWidthFraction: Metrics.bubbleMaxWidthFraction) {
            Text(text)
                .chatBodyStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.bubbleHorizontalPadding)
                .padding(.vertical, Metrics.bubbleVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.bubbleCornerRadius, style: .circular)
                        .fill(Palette.userBubble)
                )
        }
    }
}

struct TrailingBubbleLayout: Layout {
    var maxWidthFraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = bubbleWidth(available: proposal.width, subview: subview)
        let height = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let width = bubbleWidth(available: bounds.width, subview: subview)
        subview.place(
            at: CGPoint(x: bounds.maxX - width, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }

    private func bubbleWidth(available: CGFloat?, subview: LayoutSubview) -> CGFloat {
        let idealWidth = subview.sizeThatFits(.unspecified).width
        guard let available, available.isFinite else { return idealWidth }
        return min(idealWidth, available * maxWidthFraction)
    }
}
