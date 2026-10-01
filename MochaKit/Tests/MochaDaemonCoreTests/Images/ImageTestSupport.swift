import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MochaDaemonCore

struct RGBA: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var isMostlyRed: Bool {
        red > 180 && green < 80 && blue < 80
    }

    var isMostlyBlue: Bool {
        blue > 180 && red < 80 && green < 80
    }
}

enum TestImages {
    static func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mocha-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func image(width: Int, height: Int, hasAlpha: Bool = false, draw: (CGContext) -> Void) throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ))
        draw(context)
        return try #require(context.makeImage())
    }

    static func solid(width: Int, height: Int, red: CGFloat = 0.2, green: CGFloat = 0.6, blue: CGFloat = 0.3) throws -> CGImage {
        try image(width: width, height: height) { context in
            context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @discardableResult
    static func write(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        orientation: CGImagePropertyOrientation? = nil
    ) throws -> URL {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation.rawValue
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    static func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func typeIdentifier(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> RGBA {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        let offset = y * image.width * 4 + x * 4
        return RGBA(
            red: data.load(fromByteOffset: offset, as: UInt8.self),
            green: data.load(fromByteOffset: offset + 1, as: UInt8.self),
            blue: data.load(fromByteOffset: offset + 2, as: UInt8.self),
            alpha: data.load(fromByteOffset: offset + 3, as: UInt8.self)
        )
    }

    static func sparseFile(at url: URL, size: Int) throws {
        try #require(FileManager.default.createFile(atPath: url.fileSystemPath, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }

    static func setPermissions(_ permissions: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.fileSystemPath)
    }
}
