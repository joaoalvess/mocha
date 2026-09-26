import MochaProtocol
import SwiftUI

struct UsageSheet: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            Text("Uso")
                .systemText(.sheetTitle)
                .foregroundStyle(Palette.textPrimary)
            ForEach(windows, id: \.kind) { window in
                HStack(spacing: 12) {
                    Text(label(for: window.kind))
                        .font(Typography.usageLabel)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24, alignment: .trailing)
                    UsageBar(fraction: window.usedPercent / 100)
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .font(Typography.usageValue)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var windows: [UsageWindow] {
        session.usage?.windows.filter { $0.kind != .unknown } ?? []
    }

    private func label(for kind: UsageWindowKind) -> String {
        switch kind {
        case .fiveHour: "5h"
        case .weekly: "7d"
        case .unknown: "?"
        }
    }
}
