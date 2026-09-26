import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MochaClient

struct ImageReductionTests {
    private struct DecodedImage: Equatable {
        let width: Int
        let height: Int
        let orientation: Int
        let type: String
    }

    private static func bitmap(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.85, green: 0.45, blue: 0.33, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
        return try #require(context.makeImage())
    }

    private static func encoded(
        width: Int,
        height: Int,
        type: UTType = .jpeg,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation.rawValue]
        CGImageDestinationAddImage(destination, try bitmap(width: width, height: height), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func decode(_ data: Data) throws -> DecodedImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return DecodedImage(
            width: try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            height: try #require(properties[kCGImagePropertyPixelHeight] as? Int),
            orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1,
            type: try #require(CGImageSourceGetType(source) as String?)
        )
    }

    @Test func largeLandscapeImageShrinksToTheLimitKeepingTheProportion() throws {
        let reduced = try ImageReduction.reduce(Self.encoded(width: 4_000, height: 3_000))
        let decoded = try Self.decode(reduced.data)
        #expect(decoded.width == ImageReduction.maximumPixelSize)
        #expect(abs(decoded.height - 1_536) <= 1)
    }

    @Test func largePortraitImageShrinksByTheLongerSide() throws {
        let reduced = try ImageReduction.reduce(Self.encoded(width: 3_000, height: 5_000, type: .png))
        let decoded = try Self.decode(reduced.data)
        #expect(decoded.height == ImageReduction.maximumPixelSize)
        #expect(abs(decoded.width - 1_229) <= 1)
    }

    @Test func smallImageKeepsItsSize() throws {
        let decoded = try Self.decode(ImageReduction.reduce(Self.encoded(width: 800, height: 600, type: .png)).data)
        #expect(decoded.width == 800)
        #expect(decoded.height == 600)
    }

    @Test func resultIsJPEGWithTheUploadContentType() throws {
        let reduced = try ImageReduction.reduce(Self.encoded(width: 640, height: 480, type: .png))
        #expect(reduced.contentType == .jpeg)
        #expect(try Self.decode(reduced.data).type == UTType.jpeg.identifier)
    }

    @Test func exifOrientationIsAppliedToThePixels() throws {
        let rotated = try Self.encoded(width: 300, height: 100, orientation: .right)
        let decoded = try Self.decode(ImageReduction.reduce(rotated).data)
        #expect(decoded == DecodedImage(width: 100, height: 300, orientation: 1, type: UTType.jpeg.identifier))
    }

    @Test func bitmapWithOrientationIsReducedUpright() throws {
        let reduced = try ImageReduction.reduce(Self.bitmap(width: 4_096, height: 1_024), orientation: .left)
        let decoded = try Self.decode(reduced.data)
        #expect(decoded == DecodedImage(width: 512, height: 2_048, orientation: 1, type: UTType.jpeg.identifier))
    }

    @Test func unreadableDataThrows() {
        #expect(throws: ImageReductionError.unreadableImage) {
            try ImageReduction.reduce(Data("não é imagem".utf8))
        }
        #expect(throws: ImageReductionError.unreadableImage) {
            try ImageReduction.reduce(Data())
        }
    }

    @Test func thumbnailFitsTheRequestedSize() throws {
        let thumbnail = try #require(ImageReduction.thumbnail(of: Self.encoded(width: 1_200, height: 900), maximumPixelSize: 300))
        #expect(thumbnail.width == 300)
        #expect(thumbnail.height == 225)
    }
}
