import Foundation
import Security

public struct SigningIdentity: Sendable, Equatable {
    public var sha1: String
    public var name: String
    public var organizationalUnits: [String]

    public init(sha1: String, name: String, organizationalUnits: [String]) {
        self.sha1 = sha1
        self.name = name
        self.organizationalUnits = organizationalUnits
    }
}

public protocol SigningIdentityListing: Sendable {
    func codeSigningIdentities() async throws -> [SigningIdentity]
}

public enum SignatureStatus: Sendable, Equatable {
    case teamSigned
    case otherSignature(String)
    case unsigned(String)
}

public enum CodeSigningError: Error, Sendable, Equatable {
    case signingFailed(String)
}

public struct CodeSigner: Sendable {
    public static let identifier = "com.joaoalves.mochad"
    public static let codesign = "/usr/bin/codesign"
    static let timeout: Duration = .seconds(60)

    let runner: any ProcessRunning
    let identities: any SigningIdentityListing

    public init(runner: any ProcessRunning = SystemProcessRunner(), identities: (any SigningIdentityListing)? = nil) {
        self.runner = runner
        self.identities = identities ?? SecurityCommandIdentities(runner: runner)
    }

    public func identity(forTeam team: String) async throws -> SigningIdentity? {
        try await identities.codeSigningIdentities().first { $0.organizationalUnits.contains(team) }
    }

    public static func signArguments(path: String, identity: SigningIdentity) -> [String] {
        ["--force", "--sign", identity.sha1, "--identifier", identifier, "--options", "runtime", path]
    }

    public func sign(_ path: String, with identity: SigningIdentity) async throws {
        let output = try await runner.run(Self.codesign, Self.signArguments(path: path, identity: identity), timeout: Self.timeout)
        guard output.succeeded else { throw CodeSigningError.signingFailed(output.message) }
    }

    public func signatureStatus(of path: String) async -> SignatureStatus {
        let output: ProcessOutput
        do {
            output = try await runner.run(Self.codesign, ["-dr", "-", path], timeout: Self.timeout)
        } catch {
            return .unsigned(String(describing: error))
        }
        let text = output.outputText + "\n" + output.errorText
        guard output.succeeded else { return .unsigned(output.message) }
        guard let requirement = text.split(separator: "\n").first(where: { $0.contains("designated =>") }),
              let marker = requirement.range(of: "designated =>")
        else {
            return .otherSignature(output.message)
        }
        let designated = requirement[marker.upperBound...].trimmingCharacters(in: .whitespaces)
        if designated.contains("identifier \"\(Self.identifier)\""), designated.contains("anchor apple generic") {
            return .teamSigned
        }
        return .otherSignature(designated.hasPrefix("cdhash") ? "ad-hoc" : designated)
    }
}

public enum DevelopmentTeam {
    public static let xcconfigPath = "Config/Signing.xcconfig"

    public static func read(xcconfig url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "DEVELOPMENT_TEAM" else { continue }
            let value = parts[1].prefix { $0.isLetter || $0.isNumber }
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    public static func locate(from executable: URL) -> URL? {
        var directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        while directory.pathComponents.count > 1 {
            let candidate = directory.appending(path: xcconfigPath, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: candidate.fileSystemPath) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}

public struct SecurityCommandIdentities: SigningIdentityListing {
    static let security = "/usr/bin/security"
    static let timeout: Duration = .seconds(20)

    let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func codeSigningIdentities() async throws -> [SigningIdentity] {
        let listing = try await runner.run(Self.security, ["find-identity", "-v", "-p", "codesigning"], timeout: Self.timeout)
        var identities: [SigningIdentity] = []
        for (sha1, name) in Self.parseIdentities(listing.outputText) {
            let certificates = try await runner.run(Self.security, ["find-certificate", "-a", "-c", name, "-Z", "-p"], timeout: Self.timeout)
            let units = Self.parseCertificates(certificates.outputText)[sha1].map(Self.organizationalUnits(ofDER:)) ?? []
            identities.append(SigningIdentity(sha1: sha1, name: name, organizationalUnits: units))
        }
        return identities
    }

    static func parseIdentities(_ text: String) -> [(sha1: String, name: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let close = trimmed.firstIndex(of: ")"), trimmed[..<close].allSatisfy(\.isNumber) else { return nil }
            let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let hash = rest.prefix { $0.isHexDigit }
            guard hash.count == 40 else { return nil }
            let quoted = rest.dropFirst(hash.count).trimmingCharacters(in: .whitespaces)
            guard quoted.count >= 2, quoted.hasPrefix("\""), quoted.hasSuffix("\"") else { return nil }
            return (hash.uppercased(), String(quoted.dropFirst().dropLast()))
        }
    }

    static func parseCertificates(_ text: String) -> [String: Data] {
        var certificates: [String: Data] = [:]
        var hash: String?
        var body: [String]?
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("SHA-1 hash:") {
                hash = line.dropFirst("SHA-1 hash:".count).trimmingCharacters(in: .whitespaces).uppercased()
            } else if line == "-----BEGIN CERTIFICATE-----" {
                body = []
            } else if line == "-----END CERTIFICATE-----" {
                if let hash, let body, let der = Data(base64Encoded: body.joined()) {
                    certificates[hash] = der
                }
                body = nil
            } else if body != nil {
                body?.append(line)
            }
        }
        return certificates
    }

    static func organizationalUnits(ofDER der: Data) -> [String] {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1SubjectName] as CFArray, nil) as? [String: Any],
              let subject = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
              let fields = subject[kSecPropertyKeyValue as String] as? [[String: Any]]
        else { return [] }
        return fields.compactMap { field in
            guard field[kSecPropertyKeyLabel as String] as? String == kSecOIDOrganizationalUnitName as String else { return nil }
            return field[kSecPropertyKeyValue as String] as? String
        }
    }
}
