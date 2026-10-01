import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import MochaClient

final class CountingImageLoader: ImageLoading {
    private let calls = Mutex<[String]>([])
    private let failing: Set<String>
    private let delay: Duration
    private let side: Int

    init(failing: Set<String> = [], delay: Duration = .milliseconds(30), side: Int = 8) {
        self.failing = failing
        self.delay = delay
        self.side = side
    }

    var requested: [String] {
        calls.withLock { $0 }
    }

    func loadImage(path: String, maxPixelSize: Int) async throws(ImageLoadError) -> CGImage {
        calls.withLock { $0.append("\(path)@\(maxPixelSize)") }
        try? await Task.sleep(for: delay)
        guard !failing.contains(path), let image = try? TestImages.image(width: side, height: side) else { throw .notFound }
        return image
    }
}

@MainActor
struct ChatImageCacheTests {
    @Test func lookupIsSynchronousAndKeyedByPathAndSize() async throws {
        let cache = ChatImageCache(loader: CountingImageLoader())
        #expect(cache.image(for: "/a.png", maxPixelSize: 600) == nil)
        let loaded = await cache.load("/a.png", maxPixelSize: 600)
        #expect(loaded != nil)
        #expect(cache.image(for: "/a.png", maxPixelSize: 600) === loaded)
        #expect(cache.image(for: "/a.png", maxPixelSize: 4_096) == nil)
    }

    @Test func concurrentLoadsOfTheSameKeyShareOneRequest() async throws {
        let loader = CountingImageLoader(delay: .milliseconds(80))
        let cache = ChatImageCache(loader: loader)
        async let first = cache.load("/a.png", maxPixelSize: 600)
        async let second = cache.load("/a.png", maxPixelSize: 600)
        async let other = cache.load("/a.png", maxPixelSize: 4_096)
        let images = await [first, second, other]
        #expect(images.allSatisfy { $0 != nil })
        #expect(images[0] === images[1])
        #expect(loader.requested.sorted() == ["/a.png@4096", "/a.png@600"])
        _ = await cache.load("/a.png", maxPixelSize: 600)
        #expect(loader.requested.count == 2)
    }

    @Test func failedLoadIsNotCachedAndIsRetried() async throws {
        let loader = CountingImageLoader(failing: ["/missing.png"])
        let cache = ChatImageCache(loader: loader)
        #expect(await cache.load("/missing.png", maxPixelSize: 600) == nil)
        #expect(await cache.load("/missing.png", maxPixelSize: 600) == nil)
        #expect(loader.requested == ["/missing.png@600", "/missing.png@600"])
        #expect(cache.totalCost == 0)
    }

    @Test func seededImageIsServedWithoutLoading() async throws {
        let loader = CountingImageLoader()
        let cache = ChatImageCache(loader: loader)
        let seeded = try TestImages.image(width: 12, height: 9)
        cache.seed(path: "/uploads/a.jpg", image: seeded, maxPixelSize: ChatImageCache.thumbnailPixelSize)
        #expect(cache.image(for: "/uploads/a.jpg", maxPixelSize: ChatImageCache.thumbnailPixelSize) === seeded)
        #expect(await cache.load("/uploads/a.jpg", maxPixelSize: ChatImageCache.thumbnailPixelSize) === seeded)
        #expect(loader.requested.isEmpty)
    }

    @Test func seedingAListPairsPathsAndImagesInOrder() throws {
        let cache = ChatImageCache(loader: CountingImageLoader())
        let images = try [TestImages.image(width: 12, height: 9), TestImages.image(width: 9, height: 12)]
        cache.seed(paths: ["/cache/a.jpg", "/cache/b.png"], images: images, maxPixelSize: ChatImageCache.thumbnailPixelSize)
        #expect(cache.image(for: "/cache/a.jpg", maxPixelSize: ChatImageCache.thumbnailPixelSize) === images[0])
        #expect(cache.image(for: "/cache/b.png", maxPixelSize: ChatImageCache.thumbnailPixelSize) === images[1])
    }

    @Test func seedingAListWithDifferentCountsStoresNothing() throws {
        let cache = ChatImageCache(loader: CountingImageLoader())
        let image = try TestImages.image(width: 12, height: 9)
        cache.seed(paths: ["/cache/a.jpg", "/cache/b.png"], images: [image], maxPixelSize: ChatImageCache.thumbnailPixelSize)
        #expect(cache.image(for: "/cache/a.jpg", maxPixelSize: ChatImageCache.thumbnailPixelSize) == nil)
        #expect(cache.totalCost == 0)
    }

    @Test func evictsTheLeastRecentlyUsedByBytes() throws {
        let images = try (0..<3).map { _ in try TestImages.image(width: 16, height: 16) }
        let cost = ChatImageCache.cost(of: images[0])
        #expect(cost >= 16 * 16 * 4)
        let cache = ChatImageCache(loader: CountingImageLoader(), costLimit: cost * 2)
        cache.seed(path: "/a.png", image: images[0], maxPixelSize: 600)
        cache.seed(path: "/b.png", image: images[1], maxPixelSize: 600)
        #expect(cache.image(for: "/a.png", maxPixelSize: 600) != nil)
        cache.seed(path: "/c.png", image: images[2], maxPixelSize: 600)
        #expect(cache.image(for: "/b.png", maxPixelSize: 600) == nil)
        #expect(cache.image(for: "/a.png", maxPixelSize: 600) != nil)
        #expect(cache.image(for: "/c.png", maxPixelSize: 600) != nil)
        #expect(cache.totalCost == cost * 2)
    }

    @Test func largerImageEvictsAsManyAsNeededButStaysItself() throws {
        let small = try TestImages.image(width: 16, height: 16)
        let large = try TestImages.image(width: 64, height: 64)
        let cache = ChatImageCache(loader: CountingImageLoader(), costLimit: ChatImageCache.cost(of: small) * 3)
        for name in ["a", "b", "c"] {
            cache.seed(path: "/\(name).png", image: small, maxPixelSize: 600)
        }
        cache.seed(path: "/big.png", image: large, maxPixelSize: 4_096)
        #expect(cache.image(for: "/big.png", maxPixelSize: 4_096) != nil)
        #expect(["a", "b", "c"].allSatisfy { cache.image(for: "/\($0).png", maxPixelSize: 600) == nil })
        #expect(cache.totalCost == ChatImageCache.cost(of: large))
    }

    @Test func reseedingTheSameKeyReplacesItsCost() throws {
        let cache = ChatImageCache(loader: CountingImageLoader())
        let first = try TestImages.image(width: 16, height: 16)
        let second = try TestImages.image(width: 32, height: 32)
        cache.seed(path: "/a.png", image: first, maxPixelSize: 600)
        cache.seed(path: "/a.png", image: second, maxPixelSize: 600)
        #expect(cache.totalCost == ChatImageCache.cost(of: second))
        #expect(cache.image(for: "/a.png", maxPixelSize: 600) === second)
    }
}
