#if DEBUG
import MochaClient
import MochaProtocol

final class PairingProblemConnection: ServerConnection {
    let messages: AsyncStream<ServerEnvelope>
    let states: AsyncStream<ConnectionState>
    private let base: any ServerConnection

    init(base: any ServerConnection, problem: ConnectionProblem) {
        self.base = base
        messages = base.messages
        let baseStates = base.states
        states = AsyncStream { continuation in
            let task = Task {
                for await state in baseStates {
                    continuation.yield(state == .pairingRequired(nil) ? .pairingRequired(problem) : state)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func start() async {
        await base.start()
    }

    func stop() async {
        await base.stop()
    }

    func pair(_ link: PairingLink) async {
        await base.pair(link)
    }

    func send(_ message: ClientMessage, id: String) async throws {
        try await base.send(message, id: id)
    }
}
#endif
