@preconcurrency import Citadel
import Foundation
import MochaClient
import NIOCore
import NIOSSH
import Synchronization

typealias SSHByteChannel = NIOAsyncChannel<ByteBuffer, ByteBuffer>

actor SSHConnection {
    let endpoint: SSHEndpoint
    private let client: SSHClient

    private init(endpoint: SSHEndpoint, client: SSHClient) {
        self.endpoint = endpoint
        self.client = client
    }

    static func open(to endpoint: SSHEndpoint, key: SSHSigningKey) async throws(SSHSessionError) -> SSHConnection {
        let outcome = SSHHandshakeOutcome()
        let authentication = SSHPublicKeyAuthentication(
            username: endpoint.username,
            privateKey: key.sshPrivateKey,
            outcome: outcome
        )
        let validator = SSHPinnedHostKeyValidator(pin: endpoint.hostKeys, outcome: outcome)
        do {
            let client = try await SSHClient.connect(
                host: endpoint.host,
                port: endpoint.port,
                authenticationMethod: .custom(authentication),
                hostKeyValidator: .custom(validator),
                reconnect: .never,
                connectTimeout: .seconds(10)
            )
            return SSHConnection(endpoint: endpoint, client: client)
        } catch {
            if outcome.mismatchedHostKey != nil { throw .hostKeyMismatch }
            if outcome.keyRejected { throw .keyNotAuthorized }
            if let error = error as? SSHSessionError { throw error }
            if case SSHClientError.allAuthenticationOptionsFailed = error { throw .keyNotAuthorized }
            throw .connectionFailed(error.localizedDescription)
        }
    }

    var isConnected: Bool {
        client.isConnected
    }

    func openTunnelChannel(toLoopbackPort port: Int) async throws -> SSHTunnelChannel {
        let slot = SSHByteChannelSlot()
        let settings = SSHChannelType.DirectTCPIP(
            targetHost: "localhost",
            targetPort: port,
            originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        )
        _ = try await client.createDirectTCPIPChannel(using: settings) { channel in
            do {
                let wrapped = try SSHByteChannel(
                    wrappingChannelSynchronously: channel,
                    configuration: .init(isOutboundHalfClosureEnabled: true)
                )
                slot.store(wrapped)
                return channel.eventLoop.makeSucceededVoidFuture()
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
        guard let wrapped = slot.take() else { throw SSHSessionError.channelNotWrapped }
        return SSHTunnelChannel(channel: wrapped)
    }

    func close() async {
        try? await client.close()
    }
}

private final class SSHByteChannelSlot: Sendable {
    private let channel = Mutex<SSHByteChannel?>(nil)

    func store(_ value: SSHByteChannel) {
        channel.withLock { $0 = value }
    }

    func take() -> SSHByteChannel? {
        channel.withLock { value in
            defer { value = nil }
            return value
        }
    }
}

struct SSHTunnelChannel: TunnelChannel {
    let channel: SSHByteChannel

    func exchange(_ body: @Sendable (any TunnelChannelInbound, any TunnelChannelOutbound) async throws -> Void) async throws {
        try await channel.executeThenClose { inbound, outbound in
            try await body(SSHTunnelInbound(stream: inbound), SSHTunnelOutbound(writer: outbound))
        }
    }
}

private struct SSHTunnelInbound: TunnelChannelInbound {
    let stream: NIOAsyncChannelInboundStream<ByteBuffer>

    func forEachChunk(_ body: @Sendable (Data) async throws -> Void) async throws {
        for try await buffer in stream {
            try await body(Data(buffer.readableBytesView))
        }
    }
}

private struct SSHTunnelOutbound: TunnelChannelOutbound {
    let writer: NIOAsyncChannelOutboundWriter<ByteBuffer>

    func write(_ data: Data) async throws {
        try await writer.write(ByteBuffer(bytes: data))
    }

    func finish() {
        writer.finish()
    }
}
