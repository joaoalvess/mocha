import SwiftUI

enum SheetRowValueStyle {
    case plain
    case mono
    case warning
}

struct SheetListRow<Accessory: View>: View {
    let label: String
    var value: String?
    var valueStyle: SheetRowValueStyle = .plain
    var valueDot: Color?
    var isCompact = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .systemText(isCompact ? .sheetRowCompactLabel : .sheetRowLabel)
                .foregroundStyle(isCompact ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let valueDot {
                Circle()
                    .fill(valueDot)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, -3)
                    .accessibilityHidden(true)
            }
            if let value {
                valueText(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            accessory()
        }
        .padding(.leading, isCompact ? 16.3 : 16)
        .padding(.trailing, isCompact ? 16.7 : 16)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .containerValue(\.sheetRowIncludesDivider, !isCompact)
    }

    @ViewBuilder
    private func valueText(_ value: String) -> some View {
        switch valueStyle {
        case .plain:
            Text(value)
                .systemText(isCompact ? .sheetRowCompactLabel : .sheetRowLabel)
                .foregroundStyle(Palette.textSecondary)
        case .mono:
            Text(value)
                .monoText(13.5, relativeTo: .subheadline)
                .foregroundStyle(Palette.textSecondary)
        case .warning:
            Text(value)
                .systemText(isCompact ? .sheetRowCompactLabel : .sheetRowLabel)
                .foregroundStyle(Palette.dirty)
        }
    }
}

extension SheetListRow where Accessory == EmptyView {
    init(label: String, value: String?, valueStyle: SheetRowValueStyle = .plain, valueDot: Color? = nil, isCompact: Bool = false) {
        self.init(label: label, value: value, valueStyle: valueStyle, valueDot: valueDot, isCompact: isCompact) { EmptyView() }
    }
}

struct SheetFootnote: View {
    let text: Text

    var body: some View {
        text
            .systemText(.sheetNote)
            .systemLinePitch(16, size: 12)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 7)
    }
}

struct SheetListCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content()) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Palette.divider)
                            .frame(height: 1)
                    }
                    row
                        .padding(.vertical, index > 0 && row.containerValues.sheetRowIncludesDivider ? -0.5 : 0)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.toolCard))
    }
}

extension ContainerValues {
    @Entry var sheetRowIncludesDivider = false
}
