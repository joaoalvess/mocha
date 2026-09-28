import SwiftUI

struct HomeEmptyState: View {
    let showWorkspaces: () -> Void

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
            Button(action: showWorkspaces) {
                HStack(spacing: 8) {
                    LineIconView(icon: .sidebar, size: 19, strokeWidth: 1.9, color: Palette.textPrimary)
                    Text("Ver workspaces")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(Palette.toolCard))
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.top, 22)
        }
        .padding(.horizontal, 32)
        .padding(.top, Self.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
