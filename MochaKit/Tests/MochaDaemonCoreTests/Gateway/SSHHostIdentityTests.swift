import Foundation
@testable import MochaDaemonCore
import Testing

struct SSHHostIdentityTests {
    @Test func readsTheEd25519AndEcdsaKeysWithoutTheComment() throws {
        let directory = try temporarySSHDirectory([
            "ssh_host_ed25519_key.pub": "ssh-ed25519 AAAAC3Nza root@mac.local\n",
            "ssh_host_ecdsa_key.pub": "ecdsa-sha2-nistp256 AAAAE2Vj root@mac.local\n",
            "ssh_host_rsa_key.pub": "ssh-rsa AAAAB3Nza root@mac.local\n",
        ])
        #expect(SSHHostIdentity.hostKeys(in: directory) == ["ssh-ed25519 AAAAC3Nza", "ecdsa-sha2-nistp256 AAAAE2Vj"])
    }

    @Test func skipsMissingAndMalformedFiles() throws {
        let directory = try temporarySSHDirectory(["ssh_host_ecdsa_key.pub": "lixo"])
        #expect(SSHHostIdentity.hostKeys(in: directory).isEmpty)
    }

    private func temporarySSHDirectory(_ files: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        return directory
    }
}
