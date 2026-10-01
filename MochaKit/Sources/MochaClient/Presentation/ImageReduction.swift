import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageReductionError: Error, Sendable, Equatable {
    case unreadableImage
    case encodingFailed
}

public enum ImageReduction {
    public static let maximumPixelSize = 2_048
    public static let jpegQuality = 0.85

    public static func reduce(_ data: Data) throws(ImageReductionError) -> PromptImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw .unreadableImage
        }
        guard let image = downsample(source, maximumPixelSize: maximumPixelSize) else { throw .unreadableImage }
        return PromptImage(data: try jpegData(image, quality: jpegQuality), contentType: .jpeg)
    }

    public static func reduce(_ image: CGImage, orientation: CGImagePropertyOrientation) throws(ImageReductionError) -> PromptImage {
        try reduce(try jpegData(image, quality: 1, orientation: orientation))
    }

    public static func jpeg(_ image: CGImage) throws(ImageReductionError) -> Data {
        try jpegData(image, quality: jpegQuality)
    }

    public static func thumbnail(of data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        return downsample(source, maximumPixelSize: maximumPixelSize)
    }

    private static func downsample(_ source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        let limit = min(maximumPixelSize, largestSide(of: source) ?? maximumPixelSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func largestSide(of source: CGImageSource) -> Int? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(width, height)
    }

    private static func jpegData(
        _ image: CGImage,
        quality: Double,
        orientation: CGImagePropertyOrientation = .up
    ) throws(ImageReductionError) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .encodingFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyOrientation: orientation.rawValue,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
        return data as Data
    }
}
