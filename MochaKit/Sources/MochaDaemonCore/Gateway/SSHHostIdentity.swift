import Foundation

public struct SSHHostIdentity: Sendable, Equatable {
    public static let keyFileNames = ["ssh_host_ed25519_key.pub", "ssh_host_ecdsa_key.pub"]

    public var user: String
    public var hostKeys: [String]

    public init(user: String, hostKeys: [String]) {
        self.user = user
        self.hostKeys = hostKeys
    }

    public static func current(sshDirectory: URL = URL(filePath: "/etc/ssh")) -> SSHHostIdentity {
        SSHHostIdentity(user: NSUserName(), hostKeys: hostKeys(in: sshDirectory))
    }

    public static func hostKeys(in sshDirectory: URL) -> [String] {
        keyFileNames.compactMap { name in
            guard let contents = try? String(contentsOf: sshDirectory.appending(path: name), encoding: .utf8) else { return nil }
            return publicKeyLine(contents)
        }
    }

    static func publicKeyLine(_ contents: String) -> String? {
        let fields = contents.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else { return nil }
        return "\(fields[0]) \(fields[1])"
    }
}
