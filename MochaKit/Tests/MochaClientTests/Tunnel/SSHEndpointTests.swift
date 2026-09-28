import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct SSHEndpointTests {
    private static let ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMochaHostKeyEd25519"
    private static let ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYMochaHostKeyEcdsa"
    private static let gateway = URL(string: "wss://mac-do-joao.tail1234.ts.net/v1/ws")

    private static func host(user: String? = "joao", keys: [String]? = [ed25519, ecdsa]) -> HostInfo {
        HostInfo(hostName: "Mac do João", daemonVersion: "0.1.0", herdrConnected: true, sshUser: user, sshHostKeys: keys)
    }

    @Test func resolvesTheMagicDNSHostThePortAndTheUser() throws {
        let endpoint = try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: Self.host())
        #expect(endpoint.host == "mac-do-joao.tail1234.ts.net")
        #expect(endpoint.port == 22)
        #expect(endpoint.username == "joao")
    }

    @Test func refusesWithoutHostKeysAsAnOutdatedDaemon() {
        #expect(throws: SSHEndpointError.outdatedDaemon) {
            try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: Self.host(keys: nil))
        }
        #expect(throws: SSHEndpointError.outdatedDaemon) {
            try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: Self.host(keys: []))
        }
        #expect(throws: SSHEndpointError.outdatedDaemon) {
            try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: Self.host(keys: ["lixo"]))
        }
        #expect(SSHEndpointError.outdatedDaemon.errorDescription == "Atualize o mochad no Mac")
    }

    @Test func refusesWithoutTheSSHUserAsAnOutdatedDaemon() {
        #expect(throws: SSHEndpointError.outdatedDaemon) {
            try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: Self.host(user: nil))
        }
        #expect(throws: SSHEndpointError.outdatedDaemon) {
            try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: Self.host(user: "  "))
        }
    }

    @Test func refusesWithoutPairing() {
        #expect(throws: SSHEndpointError.notPaired) {
            try SSHEndpoint.resolve(gatewayURL: nil, hostInfo: Self.host())
        }
        #expect(throws: SSHEndpointError.notPaired) {
            try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: nil)
        }
    }

    @Test func pinAcceptsOnlyTheAdvertisedKeysIgnoringComments() throws {
        let pin = try #require(SSHHostKeyPin(hostKeys: [Self.ed25519, Self.ecdsa]))
        #expect(pin.accepts(Self.ed25519))
        #expect(pin.accepts(Self.ecdsa + " root@mac.local"))
        #expect(pin.accepts("  ssh-ed25519   AAAAC3NzaC1lZDI1NTE5AAAAIMochaHostKeyEd25519\n"))
        #expect(!pin.accepts("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOutraChave"))
        #expect(!pin.accepts("ssh-rsa AAAAC3NzaC1lZDI1NTE5AAAAIMochaHostKeyEd25519"))
        #expect(!pin.accepts(""))
    }

    @Test func pinReadsTheDaemonFixture() throws {
        let envelope = try JSONDecoder().decode(ServerEnvelope.self, from: Fixtures.data("protocol/server.helloOk.ssh.json"))
        guard case .helloOk(let payload) = envelope.message else {
            Issue.record("esperava helloOk")
            return
        }
        let endpoint = try SSHEndpoint.resolve(gatewayURL: Self.gateway, hostInfo: payload.host)
        for key in payload.host.sshHostKeys ?? [] {
            #expect(endpoint.hostKeys.accepts(key))
        }
    }
}
