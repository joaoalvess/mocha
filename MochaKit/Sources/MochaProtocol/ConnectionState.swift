public enum ConnectionProblem: String, Sendable, Equatable {
    case unreachable
    case daemonNotRunning
    case unauthorized
    case pairingExpired
    case protocolMismatch
}

public enum ConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case waitingToRetry(ConnectionProblem)
    case pairingRequired(ConnectionProblem?)
    case failed(ConnectionProblem)
}
