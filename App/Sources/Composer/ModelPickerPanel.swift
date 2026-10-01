import MochaClient
import MochaProtocol
import SwiftUI

struct ModelPickerPanel: View {
    let content: ModelPickerContent
    var notice: ModelPickerNotice?
    let onModel: (String) -> Void
    let onEffort: (String) -> Void
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !content.efforts.isEmpty {
                ControlsSegments(
                    items: content.efforts.map { ControlsSegmentItem(id: $0.id, title: $0.title) },
                    selectedId: content.selectedEffort,
                    accessibilityLabel: "Effort",
                    onSelect: onEffort
                )
                .padding(.bottom, 4)
            }
            if let notice {
                Text(notice.text)
                    .font(.system(size: detailSize))
                    .foregroundStyle(notice.isError ? Palette.error : Palette.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
            }
            VStack(spacing: 2) {
                ForEach(content.models) { option in
                    row(option)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mochaGlass(.composer, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modelo")
    }

    private func row(_ option: PickerOption) -> some View {
        let isSelected = option.id == content.selectedModel
        return Button { onModel(option.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(option.title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .fixedSize()
                if let detail = option.detail {
                    Text(detail)
                        .font(.system(size: detailSize))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(isSelected ? Palette.controlSel : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel([option.title, option.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ModelPickerNotice: Equatable {
    let text: String
    let isError: Bool
}

struct ControlToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .mochaGlass(.pill, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }
}
