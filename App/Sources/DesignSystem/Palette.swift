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
    static let glass = Color(hex: 0x3C3C3C)
    static let composer = Color(hex: 0x383838)
    static let controlBg = Color(hex: 0x202225)
    static let controlSel = Color(hex: 0x121416)
    static let claude = Color(hex: 0xD87454)
    static let gitAccent = Color(hex: 0xFB923C)
    static let statusOk = Color(hex: 0x00FF00)
    static let dirty = Color(hex: 0xF4B450)
    static let error = Color(hex: 0xD8383C)
    static let termText = Color(hex: 0xD4D8E0)
    static let accessoryBar = Color(hex: 0x424242)
    static let accessoryKey = Color(hex: 0x272829)
    static let black = Color(hex: 0x010102)
    static let toolBorder = Color(hex: 0x303438)
    static let badgeOk = Color(hex: 0x0F3712)
    static let badgeWarn = Color(hex: 0x342C1F)
    static let sepDot = Color(hex: 0x55595F)
    static let ringTrack = Color(hex: 0x2F3032)
    static let divider = Color(hex: 0x202223)
    static let barTrack = Color(hex: 0x191B1D)
    static let paceMark = Color(hex: 0x979899)
    static let usageBarFill = Color(.displayP3, red: 0, green: 1, blue: 0)
    static let claudeTile = Color(hex: 0x2E221F)
    static let heroBg = Color(hex: 0x120A08)
    static let heroTile = Color(hex: 0x2E1914)
    static let tableBorder = Color(hex: 0x2B2B2B)
    static let codeInner = Color(hex: 0x17191B)
    static let grabber = Color(hex: 0x47474B)
    static let ringAutoTrack = Color(hex: 0x352C47)
    static let ringAuto = Color(hex: 0xA482E6)
    static let ringPlanTrack = Color(hex: 0x1D3A38)
    static let ringPlan = Color(hex: 0x48A89E)

    static let glassChat = Color(hex: 0x424242, opacity: 0.8)
    static let glassComposer = Color(hex: 0x3E3E3E, opacity: 0.84)
    static let glassHome = Color(hex: 0x3E4E40, opacity: 0.5)
    static let glassPill = Color(hex: 0x60646A, opacity: 0.5)
    static let glassHero = Color(hex: 0x544A48, opacity: 0.5)
    static let glassBlack = Color(hex: 0x3C3C3E, opacity: 0.55)

    static let glyphOnAccent = Color(hex: 0x000000)
    static let glyphOnDirty = Color(hex: 0x1A1206)
    static let sendDisabled = Color(hex: 0x49494B)
    static let usageFootnote = Color(hex: 0x6F747B)
    static let headerButton = Color(hex: 0x9BA0AA)
    static let archivedTitle = Color(hex: 0xC9CCD0)
    static let offlineRing = Color(hex: 0x4A4E54)
    static let offlineRingGlyph = Color(hex: 0x101112)
    static let offlineBadge = Color(hex: 0x1B1D1F)
    static let offlineBadgeText = Color(hex: 0x8C939A)
    static let offlineClaude = Color(hex: 0x8A6A5E)
    static let destructive = Color(hex: 0xF0555A)
    static let stateBadgeOk = Color(hex: 0x0F2E07)
    static let stateBadgeWarn = Color(hex: 0x2A1E0D)
    static let hostTile = Color(hex: 0x1C2A1E)
    static let offlineCapsuleText = Color(hex: 0xD0D3D7)
    static let drawerHint = Color(hex: 0x5F646B)
    static let ctaText = Color(hex: 0x0A0A0A)
    static let pairingLogoTop = Color(hex: 0x221813)
    static let pairingLogoBottom = Color(hex: 0x130D0B)
    static let cameraSubtitle = Color(hex: 0xC9CCD1)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
