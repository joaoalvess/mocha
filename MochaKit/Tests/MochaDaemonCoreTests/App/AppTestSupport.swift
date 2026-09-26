import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaDaemonCore

struct ProcessCall: Sendable, Equatable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]

    init(executable: String, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    var command: String {
        ([URL(filePath: executable).lastPathComponent] + arguments).joined(separator: " ")
    }
}

final class FakeProcessRunner: ProcessRunning {
    typealias Handler = @Sendable (ProcessCall) throws -> ProcessOutput

    private let recorded = Mutex<[ProcessCall]>([])
    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var calls: [ProcessCall] {
        recorded.withLock { $0 }
    }

    var commands: [String] {
        calls.map(\.command)
    }

    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessOutput {
        let call = ProcessCall(executable: executable, arguments: arguments, environment: environment)
        recorded.withLock { $0.append(call) }
        return try handler(call)
    }
}

final class FakeHttpProbe: HttpProbing {
    struct Request: Sendable, Equatable {
        let url: URL
        let timeout: Duration
    }

    private let recorded = Mutex<[Request]>([])
    private let result: HttpProbeResult

    init(_ result: HttpProbeResult) {
        self.result = result
    }

    var requests: [Request] {
        recorded.withLock { $0 }
    }

    func get(_ url: URL, timeout: Duration) async -> HttpProbeResult {
        recorded.withLock { $0.append(Request(url: url, timeout: timeout)) }
        return result
    }
}

struct FakeKeyPresence: ApnsKeyPresenceChecking {
    let result: KeychainItemPresence

    func presence(keyId: String) -> KeychainItemPresence {
        result
    }
}

struct FakeIdentities: SigningIdentityListing {
    let identities: [SigningIdentity]

    func codeSigningIdentities() async throws -> [SigningIdentity] {
        identities
    }
}

final class FakeLocalControl: LocalControlling {
    private let statusResult: Result<LocalStatus, LocalControlError>
    private let removal: Result<Bool, LocalControlError>
    private let removed = Mutex<[DeviceID]>([])

    init(status: Result<LocalStatus, LocalControlError> = .failure(.notRunning), removal: Result<Bool, LocalControlError> = .failure(.notRunning)) {
        self.statusResult = status
        self.removal = removal
    }

    var removedIds: [DeviceID] {
        removed.withLock { $0 }
    }

    func status() async throws -> LocalStatus {
        try statusResult.get()
    }

    func pairingCode() async throws -> PairingCode {
        throw LocalControlError.notRunning
    }

    func removeDevice(_ id: DeviceID) async throws -> Bool {
        removed.withLock { $0.append(id) }
        return try removal.get()
    }
}

enum CodesignSamples {
    static let teamSigned = ProcessOutput(
        output: "designated => identifier \"com.joaoalves.mochad\" and anchor apple generic and certificate leaf[subject.OU] = TEAM123456\n",
        error: "Executable=/Users/dev/.local/bin/mochad\n"
    )
    static let adHoc = ProcessOutput(
        output: "# designated => cdhash H\"0123456789abcdef0123456789abcdef01234567\"\n",
        error: "Executable=/Users/dev/.local/bin/mochad\n"
    )
    static let unsigned = ProcessOutput(status: 1, output: "", error: "/Users/dev/.local/bin/mochad: code object is not signed at all\n")

    static func runner(_ output: ProcessOutput) -> FakeProcessRunner {
        FakeProcessRunner { _ in output }
    }
}

enum TailscaleSamples {
    static let host = "mac.example.ts.net"
    static let status = #"{"BackendState":"Running","Self":{"DNSName":"mac.example.ts.net.","HostName":"mac"}}"#

    static func serve(proxy: String) -> String {
        #"{"TCP":{"443":{"HTTPS":true}},"Web":{"mac.example.ts.net:443":{"Handlers":{"/":{"Proxy":"\#(proxy)"}}}}}"#
    }

    static func runner(serve: String, enable: ProcessOutput = ProcessOutput()) -> FakeProcessRunner {
        FakeProcessRunner { call in
            switch call.arguments {
            case ["status", "--json"]:
                return ProcessOutput(output: status)
            case ["serve", "status", "--json"]:
                return ProcessOutput(output: serve)
            default:
                return enable
            }
        }
    }
}

struct TemporaryHome {
    let url: URL
    let paths: DaemonPaths

    init(short: Bool = false) throws {
        let name = "mh-\(UUID().uuidString.prefix(8).lowercased())"
        let base = short ? URL(filePath: "/tmp", directoryHint: .isDirectory) : FileManager.default.temporaryDirectory
        url = base.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        paths = DaemonPaths(home: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to relativePath: String, permissions: Int = 0o644) throws {
        let file = url.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path(percentEncoded: false))
    }
}

func withTemporaryHome(short: Bool = false, _ body: (TemporaryHome) async throws -> Void) async throws {
    let home = try TemporaryHome(short: short)
    defer { home.remove() }
    try await body(home)
}

func fileMode(_ url: URL) -> Int? {
    var info = stat()
    guard lstat(url.path(percentEncoded: false), &info) == 0 else { return nil }
    return Int(info.st_mode & 0o777)
}

func inode(_ url: URL) -> UInt64? {
    var info = stat()
    guard lstat(url.path(percentEncoded: false), &info) == 0 else { return nil }
    return UInt64(info.st_ino)
}
