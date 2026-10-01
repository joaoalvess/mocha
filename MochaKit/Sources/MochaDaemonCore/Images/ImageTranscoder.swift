import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageTranscodingError: Error, Sendable, Equatable {
    case undecodable
    case encodingFailed
}

struct TranscodedImage: Sendable, Equatable {
    static let jpegContentType = "image/jpeg"
    static let pngContentType = "image/png"

    let data: Data
    let contentType: String
}

enum ImageTranscoder {
    static let jpegQuality = 0.85

    private static let opaqueAlphaInfos: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]

    static func transcode(fileAt url: URL, maxPixelSize: Int) -> Result<TranscodedImage, ImageTranscodingError> {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let image = thumbnail(of: source, maxPixelSize: maxPixelSize) else {
                return .failure(.undecodable)
            }
            return encode(image)
        }
    }

    private static func thumbnail(of source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let limit = min(maxPixelSize, largestSide(of: source) ?? maxPixelSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func largestSide(of source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return max(width, height)
    }

    private static func encode(_ image: CGImage) -> Result<TranscodedImage, ImageTranscodingError> {
        let hasAlpha = !opaqueAlphaInfos.contains(image.alphaInfo)
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return .failure(.encodingFailed)
        }
        let properties: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return .failure(.encodingFailed) }
        return .success(TranscodedImage(
            data: data as Data,
            contentType: hasAlpha ? TranscodedImage.pngContentType : TranscodedImage.jpegContentType
        ))
    }
}
