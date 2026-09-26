import Foundation
import Synchronization

public struct ProcessOutput: Sendable, Equatable {
    public var status: Int32
    public var standardOutput: Data
    public var standardError: Data

    public init(status: Int32 = 0, standardOutput: Data = Data(), standardError: Data = Data()) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public init(status: Int32 = 0, output: String, error: String = "") {
        self.init(status: status, standardOutput: Data(output.utf8), standardError: Data(error.utf8))
    }

    public var outputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    public var errorText: String {
        String(decoding: standardError, as: UTF8.self)
    }

    public var succeeded: Bool {
        status == 0
    }

    public var message: String {
        let error = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        return error.isEmpty ? outputText.trimmingCharacters(in: .whitespacesAndNewlines) : error
    }
}

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case notExecutable(String)
    case launchFailed(String)
    case timedOut(String)
}

public protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessOutput
}

extension ProcessRunning {
    public func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        try await run(executable, arguments, environment: [:], timeout: timeout)
    }
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: Duration) async throws -> ProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.notExecutable(executable)
        }
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = error
        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed("\(executable): \(error.localizedDescription)")
        }
        let timedOut = Mutex(false)
        let watchdog = Task {
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            timedOut.withLock { $0 = true }
            process.terminate()
        }
        async let standardOutput = Self.readToEnd(output.fileHandleForReading)
        async let standardError = Self.readToEnd(error.fileHandleForReading)
        let collected = await (standardOutput, standardError)
        var status: Int32 = -1
        for await code in exits {
            status = code
        }
        watchdog.cancel()
        if timedOut.withLock({ $0 }) {
            throw ProcessRunnerError.timedOut(([executable] + arguments).joined(separator: " "))
        }
        return ProcessOutput(status: status, standardOutput: collected.0, standardError: collected.1)
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: (try? handle.readToEnd()) ?? Data())
            }
        }
    }
}
