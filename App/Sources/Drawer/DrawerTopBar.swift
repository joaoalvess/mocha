import MochaClient
import SwiftUI

struct DrawerTopBar: View {
    @Binding var query: String
    @Binding var mode: DrawerMode
    let onSettings: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            searchField
            modePicker
            settingsButton
        }
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

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.recent, icon: .clock, label: "Recentes")
            modeButton(.tree, icon: .listRect, label: "Árvore")
        }
        .padding(.horizontal, 3)
        .frame(width: 86, height: 34)
        .background(Capsule().fill(Palette.controlBg))
        .animation(.smooth(duration: 0.2), value: mode)
    }

    private func modeButton(_ value: DrawerMode, icon: DrawerIcon, label: String) -> some View {
        let isSelected = mode == value
        return Button {
            mode = value
        } label: {
            DrawerIconView(
                icon: icon,
                size: 18,
                strokeWidth: 1.9,
                color: isSelected ? Palette.textPrimary : Palette.textSecondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if isSelected {
                    Capsule().fill(Palette.controlSel)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            DrawerIconView(icon: .gear, size: 19, strokeWidth: 1.8, color: Palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.controlBg))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Ajustes")
    }
}
