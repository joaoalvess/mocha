#if DEBUG
@preconcurrency import Citadel
import Foundation
import NIOCore
import NIOSSH
import Synchronization

struct SSHProbeTarget: Sendable, Equatable {
    var host: String
    var port = 22
    var username: String
    var pinnedHostKey: String?
}

enum SSHProbeError: Error, LocalizedError {
    case hostKeyMismatch(String)
    case channelNotWrapped

    var errorDescription: String? {
        switch self {
        case .hostKeyMismatch(let key):
            "Chave do host diferente da fixada: \(key)"
        case .channelNotWrapped:
            "O canal direct-tcpip abriu sem o NIOAsyncChannel."
        }
    }
}

typealias SSHProbeByteChannel = NIOAsyncChannel<ByteBuffer, ByteBuffer>

final class SSHProbePublicKeyAuthentication: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let privateKey: NIOSSHPrivateKey
    private var hasOffered = false

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !hasOffered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.assumeIsolated().succeed(nil)
            return
        }
        hasOffered = true
        nextChallengePromise.assumeIsolated().succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: privateKey))
            )
        )
    }
}

struct SSHProbeHostKeyPolicy: NIOSSHClientServerAuthenticationDelegate {
    let pinnedHostKey: String?
    let onHostKey: @Sendable (String) -> Void

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        onHostKey(presented)
        if let pinnedHostKey, pinnedHostKey != presented {
            validationCompletePromise.fail(SSHProbeError.hostKeyMismatch(presented))
        } else {
            validationCompletePromise.succeed(())
        }
    }
}

private final class SSHProbeChannelSlot: Sendable {
    private let channel = Mutex<SSHProbeByteChannel?>(nil)

    func store(_ value: SSHProbeByteChannel) {
        channel.withLock { $0 = value }
    }

    func take() -> SSHProbeByteChannel? {
        channel.withLock { value in
            defer { value = nil }
            return value
        }
    }
}

actor SSHProbeConnection {
    private let client: SSHClient

    private init(client: SSHClient) {
        self.client = client
    }

    static func open(
        to target: SSHProbeTarget,
        key: SSHProbeSigningKey,
        onHostKey: @escaping @Sendable (String) -> Void
    ) async throws -> SSHProbeConnection {
        let authentication = SSHProbePublicKeyAuthentication(username: target.username, privateKey: key.sshPrivateKey)
        let hostKeyPolicy = SSHProbeHostKeyPolicy(pinnedHostKey: target.pinnedHostKey, onHostKey: onHostKey)
        let client = try await SSHClient.connect(
            host: target.host,
            port: target.port,
            authenticationMethod: .custom(authentication),
            hostKeyValidator: .custom(hostKeyPolicy),
            reconnect: .never,
            connectTimeout: .seconds(10)
        )
        return SSHProbeConnection(client: client)
    }

    var isConnected: Bool {
        client.isConnected
    }

    func openDirectTCPIP(toLoopbackPort port: Int) async throws -> SSHProbeByteChannel {
        let slot = SSHProbeChannelSlot()
        let settings = SSHChannelType.DirectTCPIP(
            targetHost: "127.0.0.1",
            targetPort: port,
            originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        )
        _ = try await client.createDirectTCPIPChannel(using: settings) { channel in
            do {
                let wrapped = try SSHProbeByteChannel(
                    wrappingChannelSynchronously: channel,
                    configuration: .init(isOutboundHalfClosureEnabled: true)
                )
                slot.store(wrapped)
                return channel.eventLoop.makeSucceededVoidFuture()
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
        guard let wrapped = slot.take() else { throw SSHProbeError.channelNotWrapped }
        return wrapped
    }

    func close() async {
        try? await client.close()
    }
}
#endif
