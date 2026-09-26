#if DEBUG
import SwiftUI

struct MarkdownPreviewScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MarkdownPreviewScreen")
                    .font(Typography.headerSubtitle)
                    .foregroundStyle(Palette.textSecondary)
                MarkdownView(markdown: "Prévia de **markdown** com `código inline`.")
            }
            .padding(Metrics.contentMargin)
        }
        .background(Palette.bg.ignoresSafeArea())
    }
}
#endif
