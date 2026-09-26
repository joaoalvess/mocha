import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct CodeSigningTests {
    static let sha1 = "6A2D0785CB9649549AD65065E1DA14DB4CED877E"
    static let name = "Apple Development: Test (ABCDE12345)"
    static let pem = """
        -----BEGIN CERTIFICATE-----
        MIIBszCCAVgCCQCDurjB84QRMzAKBggqhkjOPQQDAjBgMS0wKwYDVQQDDCRBcHBs
        ZSBEZXZlbG9wbWVudDogVGVzdCAoQUJDREUxMjM0NSkxEzARBgNVBAsMClRFQU0x
        MjM0NTYxDTALBgNVBAoMBFRlc3QxCzAJBgNVBAYTAlVTMCAXDTI2MDkyNjEyMDYw
        NFoYDzIxMjYwOTAyMTIwNjA0WjBgMS0wKwYDVQQDDCRBcHBsZSBEZXZlbG9wbWVu
        dDogVGVzdCAoQUJDREUxMjM0NSkxEzARBgNVBAsMClRFQU0xMjM0NTYxDTALBgNV
        BAoMBFRlc3QxCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE
        DLTI77j3g5MI76Qvi+MIVME3v0IpMRqeqeZmpgljUoAAQX32Ki1jQ5UcXK9kTWZH
        LSpZxCDcJZl80baoTtENWjAKBggqhkjOPQQDAgNJADBGAiEAhtrDApa6ASbUJhcW
        xPJD76FQBCymTZGy4fZyswzC1BICIQDg7hCGSSdQbaPJNE86nbCLKxarZ1Uylakp
        mC5KtyZkpA==
        -----END CERTIFICATE-----
        """
    static let findIdentity = """
          1) \(sha1) "\(name)"
          2) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Outro (ZZZZZ99999)"
             2 valid identities found
        """
    static let findCertificate = """
        SHA-256 hash: 1111111111111111111111111111111111111111111111111111111111111111
        SHA-1 hash: \(sha1)
        \(pem)
        """

    static func securityRunner() -> FakeProcessRunner {
        FakeProcessRunner { call in
            switch call.arguments.first {
            case "find-identity":
                return ProcessOutput(output: findIdentity)
            case "find-certificate" where call.arguments.contains(name):
                return ProcessOutput(output: findCertificate)
            default:
                return ProcessOutput(output: "")
            }
        }
    }

    @Test func parsesTheValidIdentitiesListing() {
        let parsed = SecurityCommandIdentities.parseIdentities(Self.findIdentity)
        #expect(parsed.map(\.sha1) == [Self.sha1, "0123456789ABCDEF0123456789ABCDEF01234567"])
        #expect(parsed.map(\.name) == [Self.name, "Developer ID Application: Outro (ZZZZZ99999)"])
    }

    @Test func readsTheOrganizationalUnitOfTheCertificate() throws {
        let certificates = SecurityCommandIdentities.parseCertificates(Self.findCertificate)
        let der = try #require(certificates[Self.sha1])
        #expect(SecurityCommandIdentities.organizationalUnits(ofDER: der) == ["TEAM123456"])
    }

    @Test func picksTheIdentityWhoseOUIsTheDevelopmentTeam() async throws {
        let runner = Self.securityRunner()
        let signer = CodeSigner(runner: runner)

        let identity = try #require(try await signer.identity(forTeam: "TEAM123456"))
        #expect(identity == SigningIdentity(sha1: Self.sha1, name: Self.name, organizationalUnits: ["TEAM123456"]))
        #expect(try await signer.identity(forTeam: "OUTROTIME1") == nil)
        #expect(runner.calls.allSatisfy { $0.executable == "/usr/bin/security" })
        #expect(runner.commands.contains("security find-identity -v -p codesigning"))
        #expect(runner.commands.contains("security find-certificate -a -c \(Self.name) -Z -p"))
    }

    @Test func signsWithTheHardenedRuntimeAndTheFixedIdentifier() async throws {
        let runner = FakeProcessRunner { _ in ProcessOutput() }
        let identity = SigningIdentity(sha1: Self.sha1, name: Self.name, organizationalUnits: ["TEAM123456"])
        try await CodeSigner(runner: runner, identities: FakeIdentities(identities: [])).sign("/Users/dev/.local/bin/mochad", with: identity)
        #expect(runner.calls == [ProcessCall(
            executable: "/usr/bin/codesign",
            arguments: ["--force", "--sign", Self.sha1, "--identifier", "com.joaoalves.mochad", "--options", "runtime", "/Users/dev/.local/bin/mochad"]
        )])
    }

    @Test func signingFailureIsReported() async throws {
        let runner = FakeProcessRunner { _ in ProcessOutput(status: 1, output: "", error: "errSecInternalComponent") }
        let identity = SigningIdentity(sha1: Self.sha1, name: Self.name, organizationalUnits: [])
        await #expect(throws: CodeSigningError.signingFailed("errSecInternalComponent")) {
            try await CodeSigner(runner: runner, identities: FakeIdentities(identities: [])).sign("/tmp/mochad", with: identity)
        }
    }

    @Test func signatureStatusReadsTheDesignatedRequirement() async {
        let cases: [(ProcessOutput, SignatureStatus)] = [
            (CodesignSamples.teamSigned, .teamSigned),
            (CodesignSamples.adHoc, .otherSignature("ad-hoc")),
            (ProcessOutput(output: "designated => identifier \"mochad\" and anchor apple generic\n"), .otherSignature("identifier \"mochad\" and anchor apple generic")),
            (CodesignSamples.unsigned, .unsigned("/Users/dev/.local/bin/mochad: code object is not signed at all")),
        ]
        for (output, expected) in cases {
            let runner = CodesignSamples.runner(output)
            let status = await CodeSigner(runner: runner, identities: FakeIdentities(identities: [])).signatureStatus(of: "/Users/dev/.local/bin/mochad")
            #expect(status == expected)
            #expect(runner.commands == ["codesign -dr - /Users/dev/.local/bin/mochad"])
        }
    }

    @Test func developmentTeamComesFromTheSigningXcconfigAboveTheBinary() async throws {
        try await withTemporaryHome { home in
            try home.write("CODE_SIGN_STYLE = Automatic\nDEVELOPMENT_TEAM = ABCDE12345 // time do João\n", to: "repo/Config/Signing.xcconfig")
            try home.write("binário", to: "repo/MochaKit/.build/release/mochad")
            let binary = home.url.appending(path: "repo/MochaKit/.build/release/mochad")

            let xcconfig = try #require(DevelopmentTeam.locate(from: binary))
            #expect(xcconfig.resolvingSymlinksInPath() == home.url.appending(path: "repo/Config/Signing.xcconfig").resolvingSymlinksInPath())
            #expect(DevelopmentTeam.read(xcconfig: xcconfig) == "ABCDE12345")
        }
    }

    @Test func emptyTeamReadsAsMissing() async throws {
        try await withTemporaryHome { home in
            try home.write("DEVELOPMENT_TEAM = \n", to: "Signing.xcconfig")
            #expect(DevelopmentTeam.read(xcconfig: home.url.appending(path: "Signing.xcconfig")) == nil)
        }
    }
}
