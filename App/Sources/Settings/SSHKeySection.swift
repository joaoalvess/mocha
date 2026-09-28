import SwiftUI
import UIKit

struct SSHKeySection: View {
    @State private var publicKey: String?
    @State private var failure: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chave SSH".uppercased())
                .systemText(.sectionHeader)
                .systemLinePitch(16, size: 12)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 7)
                .accessibilityAddTraits(.isHeader)
            SheetListCard {
                Text(publicKey ?? failure ?? "—")
                    .monoText(12, relativeTo: .footnote)
                    .foregroundStyle(publicKey == nil ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Button(action: copy) {
                    Text(didCopy ? "Copiada" : "Copiar chave pública")
                        .systemText(.sheetRowAction)
                        .foregroundStyle(publicKey == nil ? Palette.textSecondary : Palette.statusOk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .disabled(publicKey == nil)
            }
            SheetFootnote(text: Text("Cole a chave em \(PairingCode.text("~/.ssh/authorized_keys", size: 12)) no Mac e ligue o Login Remoto. O túnel dos servidores web usa essa chave, liberada pelo Face ID."))
        }
        .task { load() }
    }

    private func load() {
        do {
            publicKey = try SSHKeyStore.loadOrCreate().authorizedKeysLine
        } catch {
            failure = error.localizedDescription
        }
    }

    private func copy() {
        guard let publicKey else { return }
        UIPasteboard.general.string = publicKey
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
