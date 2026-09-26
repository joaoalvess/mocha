import SwiftUI

enum Palette {
    static let bg = Color(hex: 0x1E1E1E)
    static let drawerBg = Color(hex: 0x161719)
    static let scrim = Color(hex: 0x0F0F10)
    static let textPrimary = Color(hex: 0xFCFCFC)
    static let textSecondary = Color(hex: 0x98A0A8)
    static let link = Color(hex: 0x78A0F4)
    static let userBubble = Color(hex: 0x1B351B)
    static let selectedRow = Color(hex: 0x142E16)
    static let toolCard = Color(hex: 0x121416)
    static let toolCardBorder = Color(hex: 0x303438)
    static let glass = Color(hex: 0x3C3C3C)
    static let composer = Color(hex: 0x383838)
    static let controlBg = Color(hex: 0x202225)
    static let controlSelected = Color(hex: 0x121416)
    static let claude = Color(hex: 0xD87454)
    static let gitAccent = Color(hex: 0xFB923C)
    static let statusOk = Color(hex: 0x00FF00)
    static let dirty = Color(hex: 0xF4B450)
    static let error = Color(hex: 0xD8383C)
    static let termText = Color(hex: 0xD4D8E0)
    static let accessoryBar = Color(hex: 0x424242)
    static let accessoryKey = Color(hex: 0x272829)
    static let glyphOnAccent = Color.black
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
