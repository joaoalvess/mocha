import MochaProtocol

extension ConnectionProblem {
    var message: String {
        switch self {
        case .unreachable: "Sem conexão com o Mac"
        case .daemonNotRunning: "O Mac respondeu, mas o mochad não está rodando"
        case .unauthorized: "Este iPhone não está mais pareado"
        case .pairingExpired: "Código vencido; gere outro com `mochad pair`"
        case .protocolMismatch: "O app e o mochad estão em versões incompatíveis"
        }
    }
}

extension ConnectionState {
    var statusText: String {
        switch self {
        case .idle: "Desconectado"
        case .connecting: "Conectando…"
        case .connected: "Conectado"
        case .waitingToRetry(let problem): problem.message
        case .pairingRequired(let problem): problem?.message ?? "Parear com o Mac"
        case .failed(let problem): problem.message
        }
    }
}
