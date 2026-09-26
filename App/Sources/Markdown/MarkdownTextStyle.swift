import Accessibility
import CoreText
import SwiftUI
import UIKit

typealias MarkdownLineHeightKey = AttributeScopes.CoreTextAttributes.LineHeightAttribute
typealias MarkdownHeadingLevelKey = AttributeScopes.AccessibilityAttributes.HeadingLevelAttribute

enum MarkdownTextStyle: Sendable, CaseIterable {
    case body
    case heading
    case table
    case code

    var size: CGFloat {
        switch self {
        case .body: Typography.chatBodySize
        case .heading: 16
        case .table, .code: 12
        }
    }

    var pitch: CGFloat {
        switch self {
        case .body: Typography.chatLinePitch
        case .heading: 22
        case .table, .code: 18
        }
    }

    var isBold: Bool {
        self == .heading
    }

    var inheritsFont: Bool {
        self != .heading
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .body: .body
        case .heading: .headline
        case .table, .code: .caption1
        }
    }
}

extension MonoFace {
    static func face(bold: Bool, italic: Bool) -> MonoFace {
        switch (bold, italic) {
        case (true, true): .boldItalic
        case (true, false): .bold
        case (false, true): .italic
        case (false, false): .regular
        }
    }
}

struct MarkdownLineMetrics: Sendable {
    let size: CGFloat
    let pitch: CGFloat
    let baselineShift: CGFloat
    private let fonts: [MonoFace: Font]

    init(style: MarkdownTextStyle, traits: UITraitCollection) {
        let metrics = UIFontMetrics(forTextStyle: style.textStyle)
        let size = metrics.scaledValue(for: style.size, compatibleWith: traits)
        let pitch = metrics.scaledValue(for: style.pitch, compatibleWith: traits)
        let font = UIFont(name: MonoFace.regular.rawValue, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        self.size = size
        self.pitch = pitch
        baselineShift = (pitch - font.lineHeight) / 2 + font.ascender - size
        fonts = Dictionary(uniqueKeysWithValues: MonoFace.allCases.map { ($0, Font.custom($0.rawValue, fixedSize: size)) })
    }

    var lineHeight: MarkdownLineHeightKey.Value {
        .exact(points: pitch)
    }

    func font(_ face: MonoFace) -> Font {
        fonts[face] ?? .custom(face.rawValue, fixedSize: size)
    }
}

struct MarkdownMetrics: Sendable {
    let dynamicTypeSize: DynamicTypeSize
    let body: MarkdownLineMetrics
    let heading: MarkdownLineMetrics
    let table: MarkdownLineMetrics
    let code: MarkdownLineMetrics
    let bulletInset: CGFloat
    let bulletColumn: CGFloat
    let numberInset: CGFloat
    let numberGap: CGFloat
    let quoteInset: CGFloat
    let minimumColumnWidth: CGFloat
    let maximumColumnWidth: CGFloat

    init(dynamicTypeSize: DynamicTypeSize) {
        self.dynamicTypeSize = dynamicTypeSize
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        body = MarkdownLineMetrics(style: .body, traits: traits)
        heading = MarkdownLineMetrics(style: .heading, traits: traits)
        table = MarkdownLineMetrics(style: .table, traits: traits)
        code = MarkdownLineMetrics(style: .code, traits: traits)
        let bodyMetrics = UIFontMetrics(forTextStyle: .body)
        let captionMetrics = UIFontMetrics(forTextStyle: .caption1)
        bulletInset = bodyMetrics.scaledValue(for: 12, compatibleWith: traits)
        bulletColumn = bodyMetrics.scaledValue(for: 25.3, compatibleWith: traits)
        numberInset = bodyMetrics.scaledValue(for: 8, compatibleWith: traits)
        numberGap = bodyMetrics.scaledValue(for: 10, compatibleWith: traits)
        quoteInset = bodyMetrics.scaledValue(for: 15, compatibleWith: traits)
        minimumColumnWidth = captionMetrics.scaledValue(for: 96, compatibleWith: traits)
        maximumColumnWidth = captionMetrics.scaledValue(for: 240, compatibleWith: traits)
    }

    func line(_ style: MarkdownTextStyle) -> MarkdownLineMetrics {
        switch style {
        case .body: body
        case .heading: heading
        case .table: table
        case .code: code
        }
    }
}

extension View {
    func markdownText(_ line: MarkdownLineMetrics, face: MonoFace = .regular) -> some View {
        font(line.font(face))
            .lineHeight(line.lineHeight)
            .baselineOffset(-line.baselineShift)
    }
}
