import CoreGraphics
import Foundation
import MochaClient
import Observation

typealias ComposerImageLoader = @Sendable () async throws -> PromptImage

struct ComposerAttachment: Identifiable {
    enum Content {
        case processing
        case ready(PromptImage, thumbnail: CGImage)
    }

    let id: UUID
    var content: Content

    var image: PromptImage? {
        if case .ready(let image, _) = content { image } else { nil }
    }
}

@MainActor
@Observable
final class ComposerAttachments {
    static let limit = PromptImages.limit
    nonisolated static let thumbnailPixelSize = 336

    private(set) var items: [ComposerAttachment] = []

    var isEmpty: Bool { items.isEmpty }
    var isFull: Bool { items.count >= Self.limit }
    var remainingSlots: Int { max(0, Self.limit - items.count) }
    var isProcessing: Bool { items.contains { $0.image == nil } }
    var readyImages: [PromptImage] { items.compactMap(\.image) }

    func add(_ loaders: [ComposerImageLoader]) {
        for loader in loaders.prefix(remainingSlots) {
            let id = UUID()
            items.append(ComposerAttachment(id: id, content: .processing))
            Task {
                finish(id, with: await Self.prepare(loader))
            }
        }
    }

    func remove(_ id: ComposerAttachment.ID) {
        items.removeAll { $0.id == id }
    }

    func takeAll() -> [ComposerAttachment] {
        let taken = items
        items = []
        return taken
    }

    func restore(_ attachments: [ComposerAttachment]) {
        items = Array((attachments + items).prefix(Self.limit))
    }

    private func finish(_ id: ComposerAttachment.ID, with prepared: (image: PromptImage, thumbnail: CGImage)?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard let prepared else {
            items.remove(at: index)
            return
        }
        items[index].content = .ready(prepared.image, thumbnail: prepared.thumbnail)
    }

    private nonisolated static func prepare(_ loader: ComposerImageLoader) async -> (image: PromptImage, thumbnail: CGImage)? {
        guard
            let image = try? await loader(),
            let thumbnail = ImageReduction.thumbnail(of: image.data, maximumPixelSize: thumbnailPixelSize)
        else { return nil }
        return (image, thumbnail)
    }
}
