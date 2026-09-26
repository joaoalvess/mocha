#if DEBUG
import SwiftUI

struct MarkdownPreviewScreen: View {
    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            Text("Prévia de markdown")
                .font(Typography.chatBody)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}
#endif
