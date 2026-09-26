import SwiftUI

struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 12)
            Button {
                configuration.isOn.toggle()
            } label: {
                SettingsSwitch(isOn: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? "Ativado" : "Desativado")
        .accessibilityAddTraits(.isToggle)
    }
}

private struct SettingsSwitch: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Capsule()
            .fill(isOn ? Palette.statusOk : Palette.glass)
            .frame(width: 51, height: 31)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.3), radius: 2.5, y: 2)
                    .padding(2)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.smooth(duration: 0.2), value: isOn)
            .contentShape(Capsule())
    }
}
