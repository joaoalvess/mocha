import CoreGraphics
import MochaClient
import SwiftUI

struct ImageViewerScreen: View {
    enum Phase {
        case loading
        case loaded
        case failed
    }

    let path: String
    let cache: ChatImageCache
    let onClose: () -> Void
    @State private var fullImage: CGImage?
    @State private var phase = Phase.loading
    @State private var dragProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dragProgress)
                .ignoresSafeArea()
            content
        }
        .overlay(alignment: .top) {
            toolbar
                .opacity(1 - min(1, dragProgress * 2))
        }
        .presentationBackground(.clear)
        .statusBarHidden()
        .accessibilityAction(.escape, onClose)
        .task { await loadFullImage() }
    }

    @ViewBuilder
    private var content: some View {
        if let image = displayedImage {
            ZoomableImageView(image: image, onDragProgress: { dragProgress = $0 }, onDismiss: onClose)
                .ignoresSafeArea()
        } else if phase == .failed {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 36, weight: .regular))
                Text("Não foi possível carregar a imagem")
                    .font(.system(size: 15))
            }
            .foregroundStyle(Palette.textSecondary)
        } else {
            ProgressView()
                .tint(Palette.textSecondary)
        }
    }

    private var toolbar: some View {
        HStack {
            GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .black, action: onClose)
            Spacer()
            if phase == .loading, displayedImage != nil {
                ProgressView()
                    .tint(Palette.textSecondary)
                    .accessibilityLabel("Carregando a imagem em tamanho original")
            }
            Spacer()
            shareButton
        }
        .padding(.horizontal, Metrics.contentMargin)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var shareButton: some View {
        let style = GlassRoundButtonStyle.black
        if phase != .loading, let image = displayedImage {
            ShareLink(item: ShareableImage(image: image), preview: SharePreview("Imagem", image: Image(decorative: image, scale: 1))) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: style.iconSize * 0.9, weight: .regular))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: style.diameter, height: style.diameter)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .mochaGlass(style.tint, interactive: true, in: Circle())
            .accessibilityLabel("Compartilhar imagem")
        } else {
            Color.clear
                .frame(width: style.diameter, height: style.diameter)
        }
    }

    private var displayedImage: CGImage? {
        fullImage ?? cache.image(for: path, maxPixelSize: ChatImageCache.thumbnailPixelSize)
    }

    private func loadFullImage() async {
        guard let image = await cache.load(path, maxPixelSize: ChatImageCache.fullScreenPixelSize) else {
            phase = .failed
            return
        }
        fullImage = image
        phase = .loaded
    }
}
