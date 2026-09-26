import CoreGraphics
import CoreImage
import Foundation
import MochaProtocol
import Testing
@testable import MochaDaemonCore

@Suite
struct TerminalQRCodeTests {
    static func pairingLink() throws -> PairingLink {
        PairingLink(
            url: try #require(URL(string: "wss://mac-mini.tail1234.ts.net/v1")),
            code: "q8Zk3vX0b1Ym7Rt9Lw2Nc5Pd4Hs6Jf-Ga_Ue8Ki0Oo1A"
        )
    }

    @Test func printedQRDecodesBackToThePairingLink() throws {
        let link = try Self.pairingLink()
        let text = try #require(TerminalQRCode.render(link.link.absoluteString))

        let modules = try Self.modules(fromTerminal: text)
        let image = try Self.rasterize(modules, scale: 8)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let messages = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }

        #expect(messages.count == 1)
        let decoded = try #require(messages.first.flatMap(URL.init(string:)).flatMap(PairingLink.init))
        #expect(decoded == link)
    }

    @Test func everyLineHasExplicitColorsAndTheQuietZoneIsFourModules() throws {
        let text = try #require(TerminalQRCode.render(try Self.pairingLink().link.absoluteString))
        let lines = text.split(separator: "\n")
        #expect(lines.allSatisfy { $0.hasPrefix(TerminalQRCode.colors) && $0.hasSuffix(TerminalQRCode.reset) })

        let modules = try Self.modules(fromTerminal: text)
        let firstDarkRow = try #require(modules.firstIndex { $0.contains(true) })
        let lastDarkRow = try #require(modules.lastIndex { $0.contains(true) })
        let firstDarkColumn = try #require(modules.compactMap { $0.firstIndex(of: true) }.min())
        let lastDarkColumn = try #require(modules.compactMap { $0.lastIndex(of: true) }.max())
        let width = try #require(modules.first?.count)
        #expect(firstDarkRow == TerminalQRCode.quietZone)
        #expect(firstDarkColumn == TerminalQRCode.quietZone)
        #expect(width - 1 - lastDarkColumn == TerminalQRCode.quietZone)
        #expect(modules.count - 1 - lastDarkRow >= TerminalQRCode.quietZone)
    }

    static func modules(fromTerminal text: String) throws -> [[Bool]] {
        let plain = text.replacing(/\u{1B}\[[0-9;]*m/, with: "")
        var rows: [[Bool]] = []
        for line in plain.split(separator: "\n") {
            var top: [Bool] = []
            var bottom: [Bool] = []
            for character in line {
                switch character {
                case "█": top.append(true); bottom.append(true)
                case "▀": top.append(true); bottom.append(false)
                case "▄": top.append(false); bottom.append(true)
                case " ": top.append(false); bottom.append(false)
                default: throw QRTestError.unexpectedCharacter(character)
                }
            }
            rows.append(top)
            rows.append(bottom)
        }
        return rows
    }

    static func rasterize(_ modules: [[Bool]], scale: Int) throws -> CGImage {
        let height = modules.count * scale
        let width = (modules.first?.count ?? 0) * scale
        var pixels = [UInt8](repeating: 255, count: width * height)
        for (row, values) in modules.enumerated() {
            for (column, dark) in values.enumerated() where dark {
                for y in (row * scale)..<((row + 1) * scale) {
                    for x in (column * scale)..<((column + 1) * scale) {
                        pixels[y * width + x] = 0
                    }
                }
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    enum QRTestError: Error {
        case unexpectedCharacter(Character)
    }
}
