import CoreGraphics
import Foundation

public actor SimulatedImageLibrary {
    private var images: [String: Data] = [:]

    public init() {}

    func store(_ data: Data, at path: String) {
        images[path] = data
    }

    func data(at path: String) -> Data? {
        images[path]
    }
}

public struct SimulatedImageLoader: ImageLoading {
    public static let delay: Duration = .milliseconds(350)
    static let largestSide = 1_600

    private let library: SimulatedImageLibrary?
    private let delay: Duration

    public init(library: SimulatedImageLibrary? = nil, delay: Duration = SimulatedImageLoader.delay) {
        self.library = library
        self.delay = delay
    }

    public func loadImage(path: String, maxPixelSize: Int) async throws(ImageLoadError) -> CGImage {
        do {
            try await Task.sleep(for: delay)
        } catch {
            throw .network
        }
        if let data = await library?.data(at: path) {
            guard let image = ImageReduction.thumbnail(of: data, maximumPixelSize: maxPixelSize) else { throw .undecodableImage }
            return image
        }
        guard let image = Self.gradient(for: path, maxPixelSize: maxPixelSize) else { throw .undecodableImage }
        return image
    }

    static func gradient(for path: String, maxPixelSize: Int) -> CGImage? {
        let seed = fingerprint(of: path)
        let longSide = max(1, min(maxPixelSize, largestSide))
        let shortSide = max(1, longSide * 3 / 4)
        let isPortrait = seed & 1 == 0
        let width = isPortrait ? shortSide : longSide
        let height = isPortrait ? longSide : shortSide
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        let hue = Double(seed % 360) / 360
        let shift = 0.12 + Double((seed >> 9) % 120) / 1_000
        let colors = [
            color(hue: hue, saturation: 0.55, brightness: 0.85),
            color(hue: (hue + shift).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45),
        ]
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(height)),
            end: CGPoint(x: CGFloat(width), y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        let radius = CGFloat(min(width, height)) * 0.22
        let center = CGPoint(
            x: CGFloat(width) * (0.3 + Double((seed >> 17) % 40) / 100),
            y: CGFloat(height) * (0.3 + Double((seed >> 23) % 40) / 100)
        )
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return context.makeImage()
    }

    static func fingerprint(of path: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func color(hue: Double, saturation: Double, brightness: Double) -> CGColor {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        let (red, green, blue): (Double, Double, Double) = switch index {
        case 0: (brightness, rising, low)
        case 1: (falling, brightness, low)
        case 2: (low, brightness, rising)
        case 3: (low, falling, brightness)
        case 4: (rising, low, brightness)
        default: (brightness, low, falling)
        }
        return CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
