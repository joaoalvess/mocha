import MochaProtocol

struct HubError: Error, Sendable, Equatable {
    let code: ProtocolErrorCode
    let message: String

    static let notHelloFirst = HubError(code: .unauthorized, message: "A primeira mensagem precisa ser hello.")
    static let invalidToken = HubError(code: .unauthorized, message: "Aparelho não autorizado. Pareie de novo.")
    static let deviceRemoved = HubError(code: .unauthorized, message: "Este aparelho foi removido do Mac.")
    static let pairingExpired = HubError(code: .pairingExpired, message: "O código de pareamento venceu ou já foi usado.")
    static let protocolMismatch = HubError(code: .protocolMismatch, message: "Versão de protocolo não suportada.")
    static let invalidMessage = HubError(code: .invalidPayload, message: "Mensagem inválida.")
    static let helloCredentials = HubError(code: .invalidPayload, message: "O hello precisa de deviceToken ou de pairingCode, só um dos dois.")
    static let repeatedHello = HubError(code: .invalidPayload, message: "Esta conexão já fez hello.")
    static let notClaude = HubError(code: .invalidPayload, message: "Chat disponível só para Claude Code")
    static let invalidCursor = HubError(code: .invalidPayload, message: "Cursor de página inválido.")
    static let invalidSessionId = HubError(code: .invalidPayload, message: "O sessionId precisa ser um UUID.")
    static let agentNotFound = HubError(code: .agentNotFound, message: "Agente não encontrado.")
    static let sessionNotFound = HubError(code: .sessionNotFound, message: "Sessão não encontrada no Mac.")
    static let sessionNotCurrent = HubError(code: .sessionNotFound, message: "A sessão não é a atual de nenhum agente.")
    static let agentBlocked = HubError(code: .agentBlocked, message: "O agente está esperando uma resposta no terminal.")
    static let herdrUnavailable = HubError(code: .herdrUnavailable, message: "O Herdr não está disponível no Mac.")
    static let deviceStoreFailed = HubError(code: .internal, message: "Não foi possível gravar o aparelho no Mac.")
    static let herdrFailed = HubError(code: .internal, message: "Falha ao falar com o Herdr.")
    static let transcriptFailed = HubError(code: .internal, message: "Não foi possível ler a conversa no Mac.")

    static func unknownType(_ type: String) -> HubError {
        HubError(code: .unknownType, message: "Tipo de mensagem desconhecido: \(type).")
    }

    static func herdr(_ error: HerdrBridgeError) -> HubError {
        switch error {
        case .unavailable:
            return .herdrUnavailable
        case .agentNotFound:
            return .agentNotFound
        case .agentBlocked:
            return .agentBlocked
        case .herdr(let code, _):
            switch code {
            case "agent_blocked":
                return .agentBlocked
            case "agent_not_found", "pane_not_found":
                return .agentNotFound
            case "agent_not_ready":
                return HubError(code: .internal, message: "O agente ainda não está pronto para receber mensagens.")
            case "agent_prompt_stalled":
                return HubError(code: .internal, message: "O Herdr não conseguiu entregar a mensagem ao agente.")
            case "timeout":
                return HubError(code: .internal, message: "O Herdr não respondeu a tempo.")
            default:
                return HubError(code: .internal, message: "O Herdr recusou o comando (\(code)).")
            }
        }
    }
}
