import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public enum TerminalQRCode {
    public static let quietZone = 4
    public static let correctionLevel = "M"
    static let colors = "\u{1B}[38;5;16;48;5;231m"
    static let reset = "\u{1B}[0m"

    public static func modules(for text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correctionLevel
        guard let image = filter.outputImage else { return nil }
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: width * height)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        context.render(image, toBitmap: &pixels, rowBytes: width, bounds: image.extent, format: .L8, colorSpace: nil)
        let grid = (0..<height).map { row in
            (0..<width).map { column in pixels[row * width + column] < 128 }
        }
        return trimmed(grid)
    }

    public static func render(_ text: String) -> String? {
        guard let modules = modules(for: text) else { return nil }
        let size = modules.count + 2 * quietZone
        let light = [Bool](repeating: false, count: size)
        var rows = [[Bool]](repeating: light, count: quietZone)
        for row in modules {
            rows.append([Bool](repeating: false, count: quietZone) + row + [Bool](repeating: false, count: quietZone))
        }
        rows.append(contentsOf: [[Bool]](repeating: light, count: quietZone + rows.count % 2))
        return stride(from: 0, to: rows.count, by: 2).map { index in
            let top = rows[index]
            let bottom = rows[index + 1]
            let cells = zip(top, bottom).map { character(top: $0.0, bottom: $0.1) }
            return colors + String(cells) + reset
        }.joined(separator: "\n")
    }

    static func character(top: Bool, bottom: Bool) -> Character {
        switch (top, bottom) {
        case (true, true): "█"
        case (true, false): "▀"
        case (false, true): "▄"
        case (false, false): " "
        }
    }

    private static func trimmed(_ grid: [[Bool]]) -> [[Bool]]? {
        let rows = grid.indices.filter { grid[$0].contains(true) }
        let columns = (grid.first?.indices ?? 0..<0).filter { column in grid.contains { $0[column] } }
        guard let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last else { return nil }
        return grid[top...bottom].map { Array($0[left...right]) }
    }
}
