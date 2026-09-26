import SwiftUI

enum AttachmentLayout {
    static let thumbnailSize: CGFloat = 56
    static let thumbnailRadius: CGFloat = 12
    static let thumbnailSpacing: CGFloat = 8
    static let stripBottomSpacing: CGFloat = 10
    static let removeGlyphSize: CGFloat = 20
    static let removeHitSize: CGFloat = 30
    static let menuWidth: CGFloat = 268
    static let menuRadius: CGFloat = 26
    static let menuGap: CGFloat = 8
    static let menuRowHeight: CGFloat = 52
}

struct AttachmentStrip: View {
    let attachments: [ComposerAttachment]
    let onRemove: (ComposerAttachment.ID) -> Void

    var body: some View {
        HStack(spacing: AttachmentLayout.thumbnailSpacing) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                AttachmentThumbnail(attachment: attachment, position: index + 1, total: attachments.count) {
                    onRemove(attachment.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AttachmentThumbnail: View {
    let attachment: ComposerAttachment
    let position: Int
    let total: Int
    let onRemove: () -> Void

    var body: some View {
        preview
            .frame(width: AttachmentLayout.thumbnailSize, height: AttachmentLayout.thumbnailSize)
            .background(Palette.toolCard)
            .clipShape(RoundedRectangle(cornerRadius: AttachmentLayout.thumbnailRadius, style: .continuous))
            .overlay(alignment: .topTrailing) { removeButton }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Imagem \(position) de \(total)")
    }

    @ViewBuilder
    private var preview: some View {
        switch attachment.content {
        case .processing:
            ProgressView()
                .tint(Palette.textSecondary)
                .accessibilityLabel("Preparando imagem")
        case .ready(_, let thumbnail):
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: AttachmentLayout.removeGlyphSize, height: AttachmentLayout.removeGlyphSize)
                .mochaGlass(.black, in: Circle())
                .frame(width: AttachmentLayout.removeHitSize, height: AttachmentLayout.removeHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Remover imagem \(position)")
    }
}

struct AttachMenu: View {
    let showsCamera: Bool
    let isFull: Bool
    let canPaste: Bool
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onPaste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AttachMenuRow(systemImage: "photo.on.rectangle", title: "Fotos", isEnabled: !isFull, action: onPhotos)
            if showsCamera {
                AttachMenuRow(systemImage: "camera", title: "Câmera", isEnabled: !isFull, action: onCamera)
            }
            AttachMenuRow(systemImage: "doc.on.clipboard", title: "Colar imagem", isEnabled: !isFull && canPaste, action: onPaste)
        }
        .padding(.vertical, 7)
        .frame(width: AttachmentLayout.menuWidth, alignment: .leading)
        .mochaGlass(.composer, in: RoundedRectangle(cornerRadius: AttachmentLayout.menuRadius, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 22)
    }
}

struct AttachMenuRow: View {
    let systemImage: String
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 21, height: 21)
                Text(title)
                    .font(Typography.mono(15, .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 18)
            .frame(minHeight: AttachmentLayout.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
    }
}
