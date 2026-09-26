import SwiftUI

struct SplashView: View {
    let message: String?

    var body: some View {
        ZStack {
            HomeBackground()
            VStack(spacing: 12) {
                ClaudeMark(size: 36)
                Text("Mocha")
                    .font(Typography.mono(28, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.textPrimary)
                if let message {
                    Text(message)
                        .systemText(.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Metrics.contentMargin)
        }
    }
}
