import SwiftUI

struct MarkdownCodeBlockView: View {
    let text: AttributedString
    let line: MarkdownLineMetrics
    @State private var isCopied = false

    private static let copyButtonSize: CGFloat = 32

    var body: some View {
        MarkdownHorizontalScroll(fadeColor: Palette.toolCard, showsThumb: true) {
            Text(text)
                .textSelection(.enabled)
                .fixedSize()
                .padding(.leading, 12)
                .padding(.trailing, 12 + Self.copyButtonSize)
                .padding(.top, 10)
                .padding(.bottom, 15)
        }
        .markdownText(line)
        .foregroundStyle(Palette.textPrimary)
        .background(Palette.toolCard)
        .overlay(alignment: .topTrailing) { copyButton }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var copyButton: some View {
        Button(action: copy) {
            LineIconView(
                icon: isCopied ? .check : .copy,
                size: 16,
                strokeWidth: 1.8,
                color: isCopied ? Palette.statusOk : Palette.textSecondary
            )
            .frame(width: Self.copyButtonSize, height: Self.copyButtonSize)
            .background(Palette.toolCard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .padding(.trailing, 2)
        .accessibilityLabel(isCopied ? "Copiado" : "Copiar código")
    }

    private func copy() {
        UIPasteboard.general.string = String(text.characters)
        isCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
}

struct MarkdownHorizontalScroll<Content: View>: View {
    let fadeColor: Color
    let showsThumb: Bool
    @ViewBuilder let content: () -> Content
    @State private var metrics = MarkdownScrollMetrics()

    static var fadeWidth: CGFloat { 40 }
    static var thumbWidth: CGFloat { 150 }
    static var thumbHeight: CGFloat { 3 }
    static var thumbInset: CGFloat { 12 }
    static var thumbBottom: CGFloat { 5 }
    static var thumbColor: Color { Color.white.opacity(0.3) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .fixedSize(horizontal: false, vertical: true)
        .onScrollGeometryChange(for: MarkdownScrollMetrics.self, of: MarkdownScrollMetrics.init) { _, newValue in
            metrics = newValue
        }
        .overlay(alignment: .trailing) {
            if metrics.canScrollForward {
                LinearGradient(
                    stops: [
                        .init(color: fadeColor.opacity(0), location: 0),
                        .init(color: fadeColor, location: 0.8),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.fadeWidth)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsThumb, metrics.overflows {
                thumb
            }
        }
    }

    private var thumb: some View {
        let track = max(0, metrics.containerWidth - Self.thumbInset * 2)
        let width = min(Self.thumbWidth, track)
        return Capsule()
            .fill(Self.thumbColor)
            .frame(width: width, height: Self.thumbHeight)
            .offset(x: Self.thumbInset + metrics.progress * (track - width), y: -Self.thumbBottom)
            .allowsHitTesting(false)
    }
}

struct MarkdownScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentWidth: CGFloat = 0
    var containerWidth: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.x + geometry.contentInsets.leading
        contentWidth = geometry.contentSize.width
        containerWidth = geometry.containerSize.width
    }

    var maxOffset: CGFloat {
        max(0, contentWidth - containerWidth)
    }

    var overflows: Bool {
        maxOffset > 0.5
    }

    var canScrollForward: Bool {
        overflows && offset < maxOffset - 0.5
    }

    var progress: CGFloat {
        guard overflows else { return 0 }
        return min(max(offset / maxOffset, 0), 1)
    }
}
