import Foundation
import MochaClient
import NIOCore
import NIOSSH
import Synchronization

final class SSHHandshakeOutcome: Sendable {
    private struct State {
        var offeredKey = false
        var keyRejected = false
        var mismatchedHostKey: String?
    }

    private let state = Mutex(State())

    var keyRejected: Bool {
        state.withLock { $0.keyRejected }
    }

    var mismatchedHostKey: String? {
        state.withLock { $0.mismatchedHostKey }
    }

    func claimKeyOffer() -> Bool {
        state.withLock { value in
            if value.offeredKey {
                value.keyRejected = true
                return false
            }
            value.offeredKey = true
            return true
        }
    }

    func recordMismatchedHostKey(_ key: String) {
        state.withLock { $0.mismatchedHostKey = key }
    }
}

final class SSHPublicKeyAuthentication: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let privateKey: NIOSSHPrivateKey
    private let outcome: SSHHandshakeOutcome

    init(username: String, privateKey: NIOSSHPrivateKey, outcome: SSHHandshakeOutcome) {
        self.username = username
        self.privateKey = privateKey
        self.outcome = outcome
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey), outcome.claimKeyOffer() else {
            nextChallengePromise.assumeIsolated().succeed(nil)
            return
        }
        nextChallengePromise.assumeIsolated().succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: privateKey))
            )
        )
    }
}

struct SSHPinnedHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    let pin: SSHHostKeyPin
    let outcome: SSHHandshakeOutcome

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        if pin.accepts(presented) {
            validationCompletePromise.succeed(())
        } else {
            outcome.recordMismatchedHostKey(presented)
            validationCompletePromise.fail(SSHSessionError.hostKeyMismatch)
        }
    }
}
