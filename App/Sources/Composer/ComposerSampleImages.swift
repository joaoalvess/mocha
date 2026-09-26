#if DEBUG
import CoreGraphics
import MochaClient
import SwiftUI
import UIKit

enum ComposerSampleImages {
    private struct Sample {
        let width: Int
        let height: Int
        let top: Color
        let bottom: Color
        let mark: Color
    }

    private static let samples = [
        Sample(width: 1_600, height: 1_200, top: Palette.claude, bottom: Palette.heroTile, mark: Palette.textPrimary),
        Sample(width: 1_200, height: 1_600, top: Palette.link, bottom: Palette.bg, mark: Palette.statusOk),
        Sample(width: 1_600, height: 1_600, top: Palette.badgeOk, bottom: Palette.black, mark: Palette.dirty),
        Sample(width: 2_400, height: 1_350, top: Palette.dirty, bottom: Palette.badgeWarn, mark: Palette.bg),
        Sample(width: 1_350, height: 2_400, top: Palette.textSecondary, bottom: Palette.toolCard, mark: Palette.claude),
    ]

    static func loaders(count: Int) -> [ComposerImageLoader] {
        (0..<max(0, count)).map { index in
            let sample = samples[index % samples.count]
            let colors = [sample.top, sample.bottom, sample.mark].map { UIColor($0).cgColor }
            let width = sample.width
            let height = sample.height
            return {
                guard let bitmap = drawing(width: width, height: height, colors: colors) else {
                    throw ImageReductionError.unreadableImage
                }
                return try ImageReduction.reduce(bitmap, orientation: .up)
            }
        }
    }

    private static func drawing(width: Int, height: Int, colors: [CGColor]) -> CGImage? {
        guard
            colors.count == 3,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            let gradient = CGGradient(colorsSpace: nil, colors: [colors[0], colors[1]] as CFArray, locations: [0, 1])
        else { return nil }
        let size = CGSize(width: width, height: height)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        let side = min(size.width, size.height) * 0.42
        context.setFillColor(colors[2])
        context.fillEllipse(in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side))
        return context.makeImage()
    }
}
#endif
