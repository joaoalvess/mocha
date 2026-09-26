import SwiftUI

struct SplashView: View {
    let message: String?

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Mocha")
                    .font(Typography.mono(28, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                if let message {
                    Text(message)
                        .font(Typography.chatBody)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Metrics.contentMargin)
        }
    }
}
