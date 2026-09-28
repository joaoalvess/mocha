import SwiftUI

struct HomeEmptyState: View {
    private static let topInset: CGFloat = 253

    var body: some View {
        VStack(spacing: 0) {
            ClaudeTile(size: 64, cornerRadius: 18, background: Palette.claudeTile, markSize: 36)
            Text("Nenhum agente aberto")
                .font(.system(size: 19, weight: .semibold))
                .systemLinePitch(24, size: 19)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 22)
            Text("Quando você abrir Claude ou Codex num workspace do Herdr no Mac, ele aparece aqui.")
                .font(.system(size: 15))
                .systemLinePitch(21, size: 15)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .padding(.top, Self.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
