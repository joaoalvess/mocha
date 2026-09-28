#if DEBUG
import SwiftUI
import UIKit
import WebKit

@MainActor
@Observable
final class SSHProbeModel {
    var host = ""
    var username = ""
    var sshPort = "22"
    var remotePort = "5173"
    var pinnedHostKey = ""
    private(set) var authorizedKeysLine: String?
    private(set) var keyKind: String?
    private(set) var presentedHostKey: String?
    private(set) var status = "Desconectado"
    private(set) var localURL: URL?
    private(set) var isBusy = false

    private var connection: SSHProbeConnection?
    private var forwarder: SSHProbePortForwarder?

    func loadKey() {
        do {
            let key = try SSHProbeKeyStore.loadOrCreate()
            authorizedKeysLine = key.authorizedKeysLine
            keyKind = key.kindLabel
        } catch {
            status = error.localizedDescription
        }
    }

    func resetKey() {
        SSHProbeKeyStore.delete()
        authorizedKeysLine = nil
        keyKind = nil
    }

    func copyPublicKey() {
        UIPasteboard.general.string = authorizedKeysLine
    }

    func connect() async {
        guard let port = Int(sshPort), let remote = Int(remotePort), !host.isEmpty, !username.isEmpty else {
            status = "Preencha host, usuário e portas."
            return
        }
        await disconnect()
        isBusy = true
        defer { isBusy = false }
        status = "Conectando…"
        do {
            let key = try SSHProbeKeyStore.loadOrCreate()
            let target = SSHProbeTarget(
                host: host,
                port: port,
                username: username,
                pinnedHostKey: pinnedHostKey.isEmpty ? nil : pinnedHostKey
            )
            let connection = try await SSHProbeConnection.open(to: target, key: key) { [weak self] hostKey in
                Task { @MainActor in self?.presentedHostKey = hostKey }
            }
            let forwarder = SSHProbePortForwarder(remotePort: remote) { port in
                try await connection.openDirectTCPIP(toLoopbackPort: port)
            }
            let localPort = try await forwarder.start()
            self.connection = connection
            self.forwarder = forwarder
            localURL = URL(string: "http://127.0.0.1:\(localPort)/")
            status = "Túnel 127.0.0.1:\(localPort) → Mac:\(remote)"
        } catch {
            status = error.localizedDescription
        }
    }

    func disconnect() async {
        await forwarder?.stop()
        await connection?.close()
        forwarder = nil
        connection = nil
        localURL = nil
        status = "Desconectado"
    }
}

struct SSHProbeScreen: View {
    @State private var model = SSHProbeModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    TextField("Host (100.x ou nome MagicDNS)", text: $model.host)
                    TextField("Usuário", text: $model.username)
                    TextField("Porta SSH", text: $model.sshPort)
                        .keyboardType(.numberPad)
                    TextField("Porta do servidor web", text: $model.remotePort)
                        .keyboardType(.numberPad)
                    TextField("Chave do host fixada (opcional)", text: $model.pinnedHostKey)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Section("Chave do aparelho") {
                    if let line = model.authorizedKeysLine {
                        Text(model.keyKind ?? "")
                            .font(.caption)
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copiar para o authorized_keys", action: model.copyPublicKey)
                        Button("Apagar chave", role: .destructive, action: model.resetKey)
                    } else {
                        Button("Gerar ou carregar chave", action: model.loadKey)
                    }
                }

                Section("Conexão") {
                    Text(model.status)
                        .font(.caption)
                    if let hostKey = model.presentedHostKey {
                        Text(hostKey)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("Conectar e abrir túnel") {
                        Task { await model.connect() }
                    }
                    .disabled(model.isBusy)
                    Button("Desconectar", role: .destructive) {
                        Task { await model.disconnect() }
                    }
                }

                if let url = model.localURL {
                    Section("Página") {
                        SSHProbeWebView(url: url)
                            .frame(height: 420)
                    }
                }
            }
            .navigationTitle("SSH probe")
        }
    }
}

private struct SSHProbeWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url?.host != url.host || webView.url?.port != url.port {
            webView.load(URLRequest(url: url))
        }
    }
}
#endif
