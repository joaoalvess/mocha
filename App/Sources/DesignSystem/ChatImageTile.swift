import CoreGraphics
import MochaClient
import SwiftUI

enum ChatImageLayout {
    static let singleSide: CGFloat = 200
    static let multipleSide: CGFloat = 96
    static let spacing: CGFloat = 6
    static let columns = 3
    static let cornerRadius: CGFloat = 12
    static let contentSpacing: CGFloat = 6
}

extension EnvironmentValues {
    @Entry var chatImageCache: ChatImageCache? = nil
    @Entry var chatImageViewer: ChatImageViewerPresenter? = nil
}

struct ChatImageSquare<Content: View>: View {
    let side: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        Palette.toolCard
            .frame(width: side, height: side)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: ChatImageLayout.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ChatImageLayout.cornerRadius, style: .continuous))
    }
}

struct ChatImageFill: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
    }
}

struct ChatImageLoading: View {
    var body: some View {
        ProgressView()
            .tint(Palette.textSecondary)
    }
}

struct ChatImageUnavailable: View {
    let side: CGFloat

    var body: some View {
        Image(systemName: "photo")
            .font(.system(size: side >= ChatImageLayout.singleSide ? 30 : 22, weight: .regular))
            .foregroundStyle(Palette.textSecondary)
    }
}

struct ChatImageGrid<Tile: View>: View {
    let count: Int
    let alignment: HorizontalAlignment
    @ViewBuilder let tile: (_ index: Int, _ side: CGFloat) -> Tile

    var body: some View {
        if count > 0 {
            VStack(alignment: alignment, spacing: ChatImageLayout.spacing) {
                ForEach(rowStarts, id: \.self) { start in
                    HStack(spacing: ChatImageLayout.spacing) {
                        ForEach(start..<min(start + ChatImageLayout.columns, count), id: \.self) { index in
                            tile(index, side)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        }
    }

    private var side: CGFloat {
        count == 1 ? ChatImageLayout.singleSide : ChatImageLayout.multipleSide
    }

    private var rowStarts: [Int] {
        Array(stride(from: 0, to: count, by: ChatImageLayout.columns))
    }
}

struct ChatImageStrip: View {
    let paths: [String]
    let alignment: HorizontalAlignment

    var body: some View {
        ChatImageGrid(count: paths.count, alignment: alignment) { index, side in
            ChatImageTile(path: paths[index], side: side)
                .id(paths[index])
        }
    }
}

struct ChatImageTile: View {
    let path: String
    let side: CGFloat
    @Environment(\.chatImageCache) private var cache
    @Environment(\.chatImageViewer) private var viewer
    @State private var loaded: CGImage?
    @State private var failed = false

    var body: some View {
        Button {
            viewer?.open(path)
        } label: {
            ChatImageSquare(side: side) {
                if let image = loaded ?? cache?.image(for: path, maxPixelSize: ChatImageCache.thumbnailPixelSize) {
                    ChatImageFill(image: image)
                } else if failed {
                    ChatImageUnavailable(side: side)
                } else {
                    ChatImageLoading()
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Imagem " + URL(filePath: path).lastPathComponent)
        .accessibilityHint("Abre em tela cheia")
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let cache else {
            failed = true
            return
        }
        if let cached = cache.image(for: path, maxPixelSize: ChatImageCache.thumbnailPixelSize) {
            loaded = cached
            return
        }
        if let image = await cache.load(path, maxPixelSize: ChatImageCache.thumbnailPixelSize) {
            loaded = image
        } else {
            failed = true
        }
    }
}
