import MochaClient
import MochaProtocol
import SwiftUI

struct ModelPickerPanel: View {
    let model: ModelAlias?
    let effort: EffortLevel?
    let onModel: (ModelAlias) -> Void
    let onEffort: (EffortLevel) -> Void
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if SessionControlChoices.hasEffort(model) {
                ControlsSegments(
                    items: SessionControlChoices.efforts.map { ControlsSegmentItem(id: $0.level.rawValue, title: $0.title) },
                    selectedId: effort?.rawValue,
                    accessibilityLabel: "Effort",
                    onSelect: { id in
                        guard let level = EffortLevel(rawValue: id) else { return }
                        onEffort(level)
                    }
                )
                .padding(.bottom, 4)
            }
            VStack(spacing: 2) {
                ForEach(SessionControlChoices.models) { choice in
                    row(choice)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mochaGlass(.composer, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modelo")
    }

    private func row(_ choice: ModelChoice) -> some View {
        let isSelected = choice.alias == model
        return Button { onModel(choice.alias) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(choice.title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .fixedSize()
                Text(choice.detail)
                    .font(.system(size: detailSize))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(isSelected ? Palette.controlSel : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(choice.title), \(choice.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
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
