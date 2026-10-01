import CoreGraphics
import Foundation

@MainActor
public final class ChatImageCache {
    nonisolated public static let thumbnailPixelSize = 600
    nonisolated public static let fullScreenPixelSize = 4_096
    nonisolated public static let defaultCostLimit = 120 * 1_024 * 1_024

    struct Key: Hashable {
        let path: String
        let maxPixelSize: Int
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        var lastUse: UInt64
    }

    public let costLimit: Int
    public private(set) var totalCost = 0

    private let loader: any ImageLoading
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<CGImage?, Never>] = [:]
    private var useClock: UInt64 = 0

    public init(loader: any ImageLoading, costLimit: Int = ChatImageCache.defaultCostLimit) {
        self.loader = loader
        self.costLimit = costLimit
    }

    public func image(for path: String, maxPixelSize: Int) -> CGImage? {
        let key = Key(path: path, maxPixelSize: maxPixelSize)
        guard entries[key] != nil else { return nil }
        useClock += 1
        entries[key]?.lastUse = useClock
        return entries[key]?.image
    }

    public func load(_ path: String, maxPixelSize: Int) async -> CGImage? {
        if let cached = image(for: path, maxPixelSize: maxPixelSize) {
            return cached
        }
        let key = Key(path: path, maxPixelSize: maxPixelSize)
        if let running = inFlight[key] {
            return await running.value
        }
        let loader = loader
        let task = Task { try? await loader.loadImage(path: path, maxPixelSize: maxPixelSize) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            store(image, for: key)
        }
        return image
    }

    public func seed(path: String, image: CGImage, maxPixelSize: Int) {
        store(image, for: Key(path: path, maxPixelSize: maxPixelSize))
    }

    public func seed(paths: [String], images: [CGImage], maxPixelSize: Int) {
        guard paths.count == images.count else { return }
        for (path, image) in zip(paths, images) {
            seed(path: path, image: image, maxPixelSize: maxPixelSize)
        }
    }

    public func removeAll() {
        entries.removeAll()
        totalCost = 0
    }

    static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    private func store(_ image: CGImage, for key: Key) {
        useClock += 1
        if let previous = entries[key] {
            totalCost -= previous.cost
        }
        let entry = Entry(image: image, cost: Self.cost(of: image), lastUse: useClock)
        entries[key] = entry
        totalCost += entry.cost
        evict(keeping: key)
    }

    private func evict(keeping kept: Key) {
        while totalCost > costLimit {
            guard let oldest = entries.filter({ $0.key != kept }).min(by: { $0.value.lastUse < $1.value.lastUse }) else { return }
            entries[oldest.key] = nil
            totalCost -= oldest.value.cost
        }
    }
}
