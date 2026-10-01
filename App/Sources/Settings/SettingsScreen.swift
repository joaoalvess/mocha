import Foundation
import MochaClient
import MochaProtocol
import SwiftUI

struct SettingsScreen: View {
    @Bindable var session: AppSession
    @State private var isConfirmingUnpair = false
    @State private var isUnpairing = false
    @State private var unpairFailure: String?

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pairedMacSection
                    Color.clear.frame(height: 26)
                    notificationsSection
                    Color.clear.frame(height: 26)
                    deviceSection
                    Color.clear.frame(height: 26)
                    SSHKeySection()
                    Color.clear.frame(height: 26)
                    unpairSection
                }
                .padding(.horizontal, Metrics.contentMargin)
                .padding(.top, 77)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            Text("Ajustes")
                .font(.system(size: 17, weight: .semibold))
                .systemLinePitch(22, size: 17)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 27)
                .accessibilityAddTraits(.isHeader)
            HStack {
                GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .black) {
                    session.dismissSheet()
                }
                Spacer()
            }
            .padding(.leading, Metrics.contentMargin)
            .padding(.top, 12)
        }
        .confirmationDialog("Desparear este iPhone?", isPresented: $isConfirmingUnpair, titleVisibility: .visible) {
            Button("Desparear", role: .destructive, action: unpair)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O Mac esquece este iPhone e o token sai do Keychain.")
        }
        .alert("Não foi possível desparear", isPresented: unpairFailureBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unpairFailure ?? "")
        }
    }

    private var pairedMacSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Mac pareado")
            SheetListCard {
                VStack(spacing: 0) {
                    SettingsHostRow(hostName: session.host?.hostName ?? "—", detail: hostDetail)
                    SheetListRow(label: "Conexão", value: session.connectionState.statusText, valueDot: connectionDot)
                }
                SheetListRow(label: "Herdr", value: herdrText)
            }
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Notificações")
            SheetListCard {
                Toggle(isOn: turnDoneAlertsBinding) {
                    Text("Turno concluído")
                        .systemText(.sheetRowLabel)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                .toggleStyle(SettingsSwitchStyle())
                .disabled(!canChangePreferences)
                Toggle(isOn: silenceWhileAtMacBinding) {
                    Text("Silenciar enquanto uso o Mac")
                        .systemText(.sheetRowLabel)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                .toggleStyle(SettingsSwitchStyle())
                .disabled(!canChangePreferences)
            }
            SheetFootnote(text: Text("Turno concluído avisa quando o Claude termina e o chat dele não está aberto; pedidos de aprovação sempre avisam. Com o Mac desbloqueado, os avisos ficam em silêncio, e ao bloquear toca o mais urgente."))
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(text: "Este iPhone")
            SheetListCard {
                if let profile = EmbeddedProvisioningProfile.current {
                    SheetListRow(
                        label: "Perfil de provisionamento",
                        value: profile.text(now: Date()),
                        valueStyle: profile.isExpiringSoon(now: Date()) ? .warning : .plain
                    )
                }
                SheetListRow(label: "Versão do app", value: AppVersion.current.text, valueStyle: .mono)
                SheetListRow(label: "Versão do daemon", value: session.host.map { "mochad \($0.daemonVersion)" } ?? "—", valueStyle: .mono)
            }
        }
    }

    private var unpairSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetListCard {
                Button {
                    isConfirmingUnpair = true
                } label: {
                    Text("Desparear este iPhone")
                        .systemText(.sheetRowAction)
                        .foregroundStyle(Palette.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .disabled(isUnpairing)
            }
            SheetFootnote(text: Text("Apaga o token do Keychain e avisa o Mac. Para voltar, rode \(PairingCode.text("mochad pair", size: 12))."))
        }
    }

    private var hostDetail: String {
        guard let pairedAt = session.pairedAt else { return "via Tailscale" }
        return "via Tailscale · pareado em \(pairedAt.formatted(Self.pairingDateStyle))"
    }

    private var connectionDot: Color {
        session.connectionState == .connected ? Palette.statusOk : Palette.textSecondary
    }

    private var herdrText: String {
        switch session.herdrConnected {
        case true?: "conectado ao mochad"
        case false?: "desconectado"
        case nil: "—"
        }
    }

    private var turnDoneAlertsBinding: Binding<Bool> {
        Binding(
            get: { session.preferences?.turnDoneAlerts ?? DevicePreferences().turnDoneAlerts },
            set: { isOn in
                Task { try? await session.setTurnDoneAlerts(isOn) }
            }
        )
    }

    private var silenceWhileAtMacBinding: Binding<Bool> {
        Binding(
            get: { session.preferences?.silenceWhileAtMac ?? DevicePreferences().silenceWhileAtMac },
            set: { isOn in
                Task { try? await session.setSilenceWhileAtMac(isOn) }
            }
        )
    }

    private var canChangePreferences: Bool {
        session.connectionState == .connected && session.preferences != nil
    }

    private var unpairFailureBinding: Binding<Bool> {
        Binding(
            get: { unpairFailure != nil },
            set: { if !$0 { unpairFailure = nil } }
        )
    }

    private func unpair() {
        isUnpairing = true
        Task {
            do {
                try await session.unpair()
            } catch {
                unpairFailure = (error as? AppSessionError)?.message ?? AppSessionError.notConnected.message
            }
            isUnpairing = false
        }
    }

    private static let pairingDateStyle = Date.FormatStyle()
        .day(.twoDigits)
        .month(.twoDigits)
        .locale(Locale(identifier: "pt_BR"))
}

private struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .systemText(.sectionHeader)
            .systemLinePitch(16, size: 12)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 7)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsHostRow: View {
    let hostName: String
    let detail: String

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.hostTile)
                .frame(width: 40, height: 40)
                .overlay {
                    LineIconView(icon: .laptop, size: 25, strokeWidth: 1.9, color: Palette.statusOk)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(hostName)
                    .systemText(.cardTitle)
                    .systemLinePitch(21, size: 16)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 13))
                    .systemLinePitch(17, size: 13)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

enum EmbeddedProvisioningProfile {
    static let current: ProvisioningProfile? = Bundle.main
        .url(forResource: "embedded", withExtension: "mobileprovision")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(ProvisioningProfile.init(embeddedProfile:))
}
