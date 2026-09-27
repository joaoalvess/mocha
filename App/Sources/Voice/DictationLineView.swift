import SwiftUI

struct DictationLineView: View {
    let line: DictationLine?

    var body: some View {
        if let line {
            Text(line.text)
                .font(Typography.composer)
                .lineSpacing(Typography.lineSpacing(size: Typography.composerSize, pitch: 20))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(line.isTranscript ? 3 : 2)
                .truncationMode(line.isTranscript ? .head : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(line.isTranscript ? "Ditado em andamento: \(line.text)" : line.text)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
