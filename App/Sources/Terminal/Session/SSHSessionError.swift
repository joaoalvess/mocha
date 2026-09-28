import Foundation
import MochaClient

enum SSHSessionError: Error, Equatable, LocalizedError {
    case endpoint(SSHEndpointError)
    case keyNotAuthorized
    case hostKeyMismatch
    case key(String)
    case connectionFailed(String)
    case channelNotWrapped

    var errorDescription: String? {
        switch self {
        case .endpoint(let error):
            error.errorDescription
        case .keyNotAuthorized:
            "O Mac recusou a chave SSH deste iPhone. Copie a chave pública em Ajustes e cole em ~/.ssh/authorized_keys no Mac."
        case .hostKeyMismatch:
            "A chave SSH do Mac não confere com a que o mochad informou."
        case .key(let reason):
            reason
        case .connectionFailed(let reason):
            "Não foi possível conectar ao Mac por SSH: \(reason)"
        case .channelNotWrapped:
            "O túnel SSH abriu sem o canal de dados."
        }
    }

    var pointsToSettings: Bool {
        self == .keyNotAuthorized
    }
}
