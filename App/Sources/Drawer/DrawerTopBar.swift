import MochaClient
import SwiftUI

struct DrawerTopBar: View {
    @Binding var query: String
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        searchField
            .frame(minHeight: DrawerLayout.topBarHeight)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            DrawerIconView(icon: .search, size: 19, strokeWidth: 2, color: Palette.textSecondary)
            TextField(
                "",
                text: $query,
                prompt: Text("Buscar workspaces, agentes…").foregroundStyle(Palette.textSecondary)
            )
            .drawerText(.search)
            .foregroundStyle(Palette.textPrimary)
            .tint(Palette.statusOk)
            .lineLimit(1)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isSearchFocused)
            .accessibilityLabel("Buscar workspaces, agentes")
        }
        .padding(.leading, 13)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: DrawerLayout.topBarHeight)
        .background(Capsule().fill(Palette.barTrack))
        .contentShape(Capsule())
        .onTapGesture { isSearchFocused = true }
    }
}
