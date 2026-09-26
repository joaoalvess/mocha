import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct PairingGateTests {
    @Test func startsHidden() {
        let gate = PairingGate()
        #expect(!gate.showsPairing)
        #expect(gate.problem == nil)
    }

    @Test func pairingRequiredCoversTheAppAndAsksToCloseOverlays() {
        var gate = PairingGate()
        let coveredWhileConnecting = gate.apply(.connecting)
        let coveredWhenConnected = gate.apply(.connected)
        let coveredWhenRequired = gate.apply(.pairingRequired(.unauthorized))
        #expect(!coveredWhileConnecting)
        #expect(!coveredWhenConnected)
        #expect(coveredWhenRequired)
        #expect(gate.showsPairing)
        #expect(gate.problem == .unauthorized)
        let coveredAgain = gate.apply(.pairingRequired(.pairingExpired))
        #expect(!coveredAgain)
        #expect(gate.problem == .pairingExpired)
    }

    @Test func staysUpInBackgroundAndWhileRetryingUntilConnected() {
        var gate = PairingGate()
        gate.apply(.pairingRequired(.unauthorized))
        gate.apply(.idle)
        #expect(gate.showsPairing)
        gate.apply(.connecting)
        gate.apply(.waitingToRetry(.unreachable))
        #expect(gate.showsPairing)
        #expect(gate.problem == .unauthorized)
        gate.apply(.connected)
        #expect(!gate.showsPairing)
        #expect(gate.problem == nil)
    }

    @Test func attemptShowsTheHostAndClearsTheLastProblem() throws {
        var gate = PairingGate()
        gate.apply(.pairingRequired(.pairingExpired))
        let link = PairingLink(url: try #require(URL(string: "wss://mac-mini.tail1234.ts.net/v1")), code: "abc")
        let covered = gate.begin(link)
        #expect(!covered)
        #expect(gate.connectingHost == "mac-mini")
        #expect(gate.problem == nil)
        gate.apply(.connecting)
        #expect(gate.connectingHost == "mac-mini")
        gate.apply(.pairingRequired(.daemonNotRunning))
        #expect(gate.connectingHost == nil)
        #expect(gate.problem == .daemonNotRunning)
    }

    @Test func attemptFromTheHomeCoversTheAppUntilItSucceeds() throws {
        var gate = PairingGate()
        gate.apply(.connected)
        let link = PairingLink(url: try #require(URL(string: "ws://127.0.0.1:47421/v1")), code: "abc")
        let covered = gate.begin(link)
        #expect(covered)
        #expect(gate.showsPairing)
        #expect(gate.connectingHost == "127")
        gate.apply(.connected)
        #expect(!gate.showsPairing)
    }

    @Test func attemptEndingInFailureKeepsTheProblemOnScreen() throws {
        var gate = PairingGate()
        gate.apply(.connected)
        gate.begin(PairingLink(url: try #require(URL(string: "wss://mac.example.ts.net/v1")), code: "abc"))
        gate.apply(.failed(.protocolMismatch))
        #expect(gate.showsPairing)
        #expect(gate.problem == .protocolMismatch)
    }

    @Test func attemptInterruptedByBackgroundEnds() throws {
        var gate = PairingGate()
        gate.apply(.pairingRequired(nil))
        gate.begin(PairingLink(url: try #require(URL(string: "wss://mac.example.ts.net/v1")), code: "abc"))
        gate.apply(.idle)
        #expect(gate.connectingHost == nil)
        #expect(gate.showsPairing)
        #expect(gate.problem == nil)
    }

    @Test func offlineStatesDoNotCoverAPairedApp() {
        var gate = PairingGate()
        gate.apply(.connected)
        let coveredWhileRetrying = gate.apply(.waitingToRetry(.unreachable))
        let coveredWhenFailed = gate.apply(.failed(.protocolMismatch))
        let coveredWhenIdle = gate.apply(.idle)
        #expect(!coveredWhileRetrying)
        #expect(!coveredWhenFailed)
        #expect(!coveredWhenIdle)
        #expect(!gate.showsPairing)
    }
}
