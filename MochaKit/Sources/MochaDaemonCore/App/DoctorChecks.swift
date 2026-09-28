import Foundation

public enum DoctorChecks {
    public static let stoppedHint = "mochad parado: rode mochad install ou scripts/run-daemon.sh"

    public static func daemon(_ result: Result<LocalStatus, LocalControlError>, now: Date) -> DoctorItem {
        switch result {
        case .success(let status):
            let clients = status.clients.count == 1 ? "1 cliente" : "\(status.clients.count) clientes"
            return DoctorItem("mochad", .ok, "rodando · \(status.version) · no ar há \(ElapsedText.since(status.startedAt, now: now)) · \(clients)")
        case .failure(.notRunning):
            return DoctorItem("mochad", .failure, stoppedHint)
        case .failure(let error):
            return DoctorItem("mochad", .failure, "o canal local não respondeu (\(describe(error)))")
        }
    }

    public static func herdr(_ ping: HerdrPing, socketPath: String) -> DoctorItem {
        switch ping {
        case .missingSocket(let path):
            return DoctorItem("Herdr", .failure, "o socket não existe em \(path)")
        case .failed(let detail):
            return DoctorItem("Herdr", .failure, "ping falhou: \(detail)", details: ["socket: \(socketPath)"])
        case .reachable(let info):
            let summary = "\(info.version) · protocolo \(info.protocolVersion) · \(socketPath)"
            guard let warning = info.protocolWarning else { return DoctorItem("Herdr", .ok, summary) }
            return DoctorItem("Herdr", .warning, summary, details: [warning])
        }
    }

    public static func agentList(_ count: HerdrAgentCount) -> DoctorItem {
        switch count {
        case .missingSocket:
            return DoctorItem("agent.list", .failure, "sem o socket do Herdr")
        case .failed(let detail):
            return DoctorItem("agent.list", .failure, detail)
        case .counted(let total, let claude):
            return DoctorItem("agent.list", .ok, "\(total) \(total == 1 ? "agente" : "agentes"), \(claude) do Claude Code")
        }
    }

    public static func hooks(_ inspection: ClaudeSettingsInspection) -> DoctorItem {
        let expected = HookEventName.allCases.map(\.rawValue)
        switch inspection {
        case .missing:
            return DoctorItem("Hooks", .warning, "não instalados: sem ~/.claude/settings.json (mochad install-hooks)")
        case .unreadable:
            return DoctorItem("Hooks", .warning, "não consegui ler ~/.claude/settings.json")
        case .hooks(let summary):
            let missing = expected.filter { !summary.mochaEvents.contains($0) }
            if missing.isEmpty {
                return DoctorItem("Hooks", .ok, "instalados em \(expected.joined(separator: ", "))")
            }
            if missing.count == expected.count {
                return DoctorItem("Hooks", .warning, "não instalados (mochad install-hooks)")
            }
            return DoctorItem("Hooks", .warning, "incompletos: faltam \(missing.joined(separator: ", ")) (mochad install-hooks)")
        }
    }

    public static func moshiHook(_ inspection: ClaudeSettingsInspection) -> DoctorItem {
        switch inspection {
        case .missing:
            return DoctorItem("moshi-hook", .ok, "ausente (sem ~/.claude/settings.json)")
        case .unreadable:
            return DoctorItem("moshi-hook", .warning, "não consegui ler ~/.claude/settings.json")
        case .hooks(let summary) where summary.moshiEvents.isEmpty:
            return DoctorItem("moshi-hook", .ok, "ausente")
        case .hooks(let summary):
            return DoctorItem(
                "moshi-hook",
                .warning,
                "instalado em \(summary.moshiEvents.joined(separator: ", "))",
                details: ["antes da 1b: moshi-hook uninstall e depois brew services stop moshi-hook"]
            )
        }
    }

    public static func codex(executable: String?, version: String?, socketReady: Bool) -> DoctorItem {
        guard let executable else {
            return DoctorItem("Codex", .warning, "codex não encontrado; tabs Codex ficam indisponíveis")
        }
        let summary = "\(version ?? "versão desconhecida") · \(executable) · App Server \(socketReady ? "no ar" : "fora do ar")"
        var notes: [String] = []
        if let version, ClaudeCodeVersion.isNewer(version, than: CodexExecutable.lastValidatedVersion) {
            notes.append("versão mais nova que a \(CodexExecutable.lastValidatedVersion) validada")
        }
        if !socketReady {
            notes.append("o mochad sobe o App Server; rode o mochad e confira de novo")
        }
        return DoctorItem("Codex", notes.isEmpty ? .ok : .warning, summary, details: notes)
    }

    public static func serve(_ diagnosis: ServeDiagnosis, setupCommand: String, expectedTarget: String) -> DoctorItem {
        switch diagnosis {
        case .ready(let host):
            return DoctorItem("Serve", .ok, "https://\(host) → \(expectedTarget), \(Gateway.healthPath) 200")
        case .missingHandler(let host):
            return DoctorItem("Serve", .failure, "sem handler em \(host):443", details: ["rode mochad serve-setup --apply (\(setupCommand))"])
        case .unixTarget(let host, let target):
            return DoctorItem(
                "Serve",
                .failure,
                "\(host):443 aponta para \(target): a extensão do Tailscale não abre socket Unix",
                details: ["troque por \(expectedTarget): mochad serve-setup --apply"]
            )
        case .unexpectedTarget(let host, let target):
            return DoctorItem("Serve", .failure, "\(host):443 aponta para \(target), e não para \(expectedTarget)", details: ["rode mochad serve-setup --apply"])
        case .gatewayNotListening(let host):
            return DoctorItem("Serve", .failure, "Serve ativo, gateway sem escutar (https://\(host) respondeu 502)")
        case .certificatePending(let host):
            return DoctorItem("Serve", .warning, "timeout no TLS de https://\(host): certificado sendo emitido; tente de novo em 1 min")
        case .healthFailed(let host, let detail):
            return DoctorItem("Serve", .failure, "https://\(host)\(Gateway.healthPath): \(detail)")
        case .tailscaleUnavailable(let detail):
            return DoctorItem("Serve", .failure, detail)
        }
    }

    public static func apns(
        config: Result<ApnsConfig?, any Error>,
        signature: SignatureStatus,
        binary: String,
        keychain: (ApnsConfig) -> KeychainItemPresence,
        issues: [ApnsConfigurationIssue] = []
    ) -> DoctorItem {
        var parts: [(DoctorStatus, String)] = []
        switch config {
        case .failure:
            parts.append((.failure, "config.json inválido"))
        case .success(nil):
            parts.append((.warning, "sem config (mochad apns import <arquivo.p8> --key-id <KID> --team-id <TID>)"))
        case .success(let config?):
            parts.append((.ok, "config presente (key \(config.keyId), team \(config.teamId))"))
            switch keychain(config) {
            case .present:
                parts.append((.ok, "chave \(config.keyId) no Keychain"))
            case .missing:
                parts.append((.failure, "chave \(config.keyId) ausente do Keychain (mochad apns import)"))
            case .failed(let status):
                parts.append((.warning, "o Keychain respondeu \(status) ao procurar a chave \(config.keyId)"))
            }
        }
        switch signature {
        case .teamSigned:
            parts.append((.ok, "\(binary) assinado pelo time (\(CodeSigner.identifier))"))
        case .otherSignature(let requirement):
            parts.append((.warning, "\(binary) sem a assinatura do time (\(requirement)): o Keychain vai pedir autorização"))
        case .unsigned(let detail):
            parts.append((.warning, "\(binary) sem assinatura (\(detail)): o Keychain vai pedir autorização"))
        }
        for issue in issues {
            parts.append((
                .failure,
                "o APNs \(issue.environment.rawValue) recusou o último envio com \(issue.status) \(issue.reason): \(apnsHint(for: issue))"
            ))
        }
        let status = parts.map(\.0).max() ?? .ok
        return DoctorItem("APNs", status, status == .ok ? "pronto" : "com pendências", details: parts.map { "\($0.0.symbol) \($0.1)" })
    }

    private static func apnsHint(for issue: ApnsConfigurationIssue) -> String {
        switch issue.reason {
        case "BadEnvironmentKeyInToken", "BadEnvironmentKeyIdInToken":
            "a chave não vale para \(issue.environment.rawValue); importe uma chave desse ambiente (mochad apns import)"
        case "InvalidProviderToken":
            "Key ID, Team ID ou chave inválidos (mochad apns import)"
        case "TopicDisallowed":
            "o bundle do config.json não aceita push com essa chave"
        default:
            "confira a chave e o config.json"
        }
    }

    public static func dataDirectory(_ paths: DaemonPaths) -> DoctorItem {
        let directory = paths.supportDirectory
        guard let mode = permissions(of: directory) else {
            return DoctorItem("Dados", .warning, "\(paths.display(directory)) ainda não existe (mochad install ou mochad run cria)")
        }
        var problems: [String] = []
        if mode & 0o077 != 0 {
            problems.append("chmod 700 \"\(directory.fileSystemPath)\" (hoje \(String(mode, radix: 8)))")
        }
        for file in [paths.configFile, paths.devicesFile, paths.sessionsFile, paths.controlSocket] {
            guard let fileMode = permissions(of: file), fileMode & 0o077 != 0 else { continue }
            problems.append("chmod 600 \"\(file.fileSystemPath)\" (hoje \(String(fileMode, radix: 8)))")
        }
        guard problems.isEmpty else {
            return DoctorItem("Dados", .warning, "permissões abertas em \(paths.display(directory))", details: problems)
        }
        return DoctorItem("Dados", .ok, "\(paths.display(directory)) 700, arquivos 600")
    }

    public static func transcript(_ result: Result<LocalStatus, LocalControlError>) -> DoctorItem {
        guard case .success(let status) = result else {
            return DoctorItem("Transcript", .warning, "precisa do daemon (mochad parado)")
        }
        guard !status.sessions.isEmpty else {
            return DoctorItem("Transcript", .ok, "nenhuma sessão acompanhada agora (validado até o Claude \(ClaudeCodeVersion.lastValidated))")
        }
        var worst = DoctorStatus.ok
        var details: [String] = []
        for session in status.sessions {
            var notes: [String] = []
            if let version = session.claudeVersion, ClaudeCodeVersion.isNewer(version) {
                notes.append("versão mais nova que a \(ClaudeCodeVersion.lastValidated) validada")
            }
            if session.dropped > 0 {
                notes.append("linhas descartadas")
            }
            if !session.unknown.isEmpty {
                notes.append("tipos desconhecidos")
            }
            let status: DoctorStatus = notes.isEmpty ? .ok : .warning
            worst = max(worst, status)
            var line = "\(status.symbol) \(session.sessionId.prefix(8)) · \(session.agentId ?? "sem agente") · Claude \(session.claudeVersion ?? "?")"
            line += " · \(session.dropped) descartadas · \(session.orphanResults) resultados órfãos"
            if !session.unknown.isEmpty {
                line += " · desconhecidos: " + session.unknown.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
            }
            if !notes.isEmpty {
                line += " — " + notes.joined(separator: "; ")
            }
            details.append(line)
        }
        let count = status.sessions.count == 1 ? "1 sessão acompanhada" : "\(status.sessions.count) sessões acompanhadas"
        return DoctorItem("Transcript", worst, "\(count) (validado até o Claude \(ClaudeCodeVersion.lastValidated))", details: details)
    }

    public static func describe(_ error: LocalControlError) -> String {
        switch error {
        case .notRunning:
            return "mochad parado"
        case .timedOut:
            return "sem resposta em 5 s"
        case .connectionFailed(let detail):
            return detail
        case .invalidResponse:
            return "resposta inválida"
        case .unexpectedStatus(let code, let message):
            return message.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(message)"
        }
    }

    private static func permissions(of url: URL) -> Int? {
        var info = stat()
        guard lstat(url.fileSystemPath, &info) == 0 else { return nil }
        return Int(info.st_mode & 0o777)
    }
}
