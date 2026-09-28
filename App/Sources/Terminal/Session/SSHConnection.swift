@preconcurrency import Citadel
import Foundation
import MochaClient
import NIOCore
import NIOSSH
import Synchronization

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
        let slot = SSHTunnelChannelSlot()
        let settings = SSHChannelType.DirectTCPIP(
            targetHost: "localhost",
            targetPort: port,
            originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        )
        _ = try await client.createDirectTCPIPChannel(using: settings) { channel in
            let (inbound, continuation) = AsyncThrowingStream<ByteBuffer, any Error>.makeStream()
            do {
                try channel.pipeline.syncOperations.addHandler(SSHTunnelInboundHandler(continuation: continuation))
                slot.store(SSHTunnelChannel(channel: channel, inbound: inbound))
                return channel.eventLoop.makeSucceededVoidFuture()
            } catch {
                continuation.finish(throwing: error)
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
        guard let wrapped = slot.take() else { throw SSHSessionError.channelNotWrapped }
        return wrapped
    }

    func close() async {
        try? await client.close()
    }
}

private final class SSHTunnelChannelSlot: Sendable {
    private let channel = Mutex<SSHTunnelChannel?>(nil)

    func store(_ value: SSHTunnelChannel) {
        channel.withLock { $0 = value }
    }

    func take() -> SSHTunnelChannel? {
        channel.withLock { value in
            defer { value = nil }
            return value
        }
    }
}

struct SSHTunnelChannel: TunnelChannel {
    let channel: any Channel
    let inbound: AsyncThrowingStream<ByteBuffer, any Error>

    func exchange(_ body: @Sendable (any TunnelChannelInbound, any TunnelChannelOutbound) async throws -> Void) async throws {
        defer { channel.close(promise: nil) }
        try await body(SSHTunnelInbound(stream: inbound), SSHTunnelOutbound(channel: channel))
    }
}

private final class SSHTunnelInboundHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let continuation: AsyncThrowingStream<ByteBuffer, any Error>.Continuation

    init(continuation: AsyncThrowingStream<ByteBuffer, any Error>.Continuation) {
        self.continuation = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        continuation.yield(unwrapInboundIn(data))
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case .some(ChannelEvent.inputClosed) = event as? ChannelEvent {
            continuation.finish()
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        continuation.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        continuation.finish(throwing: error)
    }
}

private struct SSHTunnelInbound: TunnelChannelInbound {
    let stream: AsyncThrowingStream<ByteBuffer, any Error>

    func forEachChunk(_ body: @Sendable (Data) async throws -> Void) async throws {
        for try await buffer in stream {
            try await body(Data(buffer.readableBytesView))
        }
    }
}

private struct SSHTunnelOutbound: TunnelChannelOutbound {
    let channel: any Channel

    func write(_ data: Data) async throws {
        try await channel.writeAndFlush(ByteBuffer(bytes: data))
    }

    func finish() {
        channel.close(mode: .output, promise: nil)
    }
}
