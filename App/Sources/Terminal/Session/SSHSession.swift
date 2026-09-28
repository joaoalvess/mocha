import Foundation
import MochaClient

actor SSHSession {
    private var connection: SSHConnection?
    private var pendingConnection: Task<SSHConnection, any Error>?
    private var generation = 0

    func connect(to endpoint: SSHEndpoint) async throws -> SSHConnection {
        if let connection, connection.endpoint == endpoint, await connection.isConnected {
            return connection
        }
        if let pendingConnection {
            return try await pendingConnection.value
        }
        generation += 1
        let current = generation
        let previous = connection
        connection = nil
        let task = Task { () throws -> SSHConnection in
            await previous?.close()
            let key: SSHSigningKey
            do {
                key = try SSHKeyStore.loadOrCreate()
            } catch {
                throw SSHSessionError.key(error.localizedDescription)
            }
            return try await SSHConnection.open(to: endpoint, key: key)
        }
        pendingConnection = task
        let result = await task.result
        guard current == generation else {
            if case .success(let stale) = result { await stale.close() }
            throw CancellationError()
        }
        pendingConnection = nil
        let opened = try result.get()
        connection = opened
        return opened
    }

    func openTunnelChannel(to endpoint: SSHEndpoint, remotePort: Int) async throws -> any TunnelChannel {
        let connection = try await connect(to: endpoint)
        return try await connection.openTunnelChannel(toLoopbackPort: remotePort)
    }

    func disconnect() async {
        generation += 1
        pendingConnection?.cancel()
        pendingConnection = nil
        let previous = connection
        connection = nil
        await previous?.close()
    }
}
