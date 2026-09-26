import Foundation
import MochaProtocol
import Network
import Synchronization

public enum LocalControlError: Error, Sendable, Equatable {
    case notRunning
    case timedOut
    case connectionFailed(String)
    case invalidResponse
    case unexpectedStatus(Int, String)
}

public struct LocalControlResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data
}

public protocol LocalControlling: Sendable {
    func status() async throws -> LocalStatus
    func pairingCode() async throws -> PairingCode
    func removeDevice(_ id: DeviceID) async throws -> Bool
}

public struct LocalControlClient: LocalControlling {
    public static let timeout: Duration = .seconds(5)
    static let maximumResponseSize = 4 << 20

    public let socketPath: String
    let timeout: Duration

    public init(socketPath: String = DaemonPaths().controlSocket.path(percentEncoded: false), timeout: Duration = LocalControlClient.timeout) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func status() async throws -> LocalStatus {
        let response = try await send(.get, LocalControl.statusPath)
        try Self.expect(200, response)
        return try Self.decode(LocalStatus.self, response)
    }

    public func pairingCode() async throws -> PairingCode {
        let response = try await send(.post, LocalControl.pairingCodePath)
        try Self.expect(200, response)
        return try Self.decode(PairingCode.self, response)
    }

    public func removeDevice(_ id: DeviceID) async throws -> Bool {
        guard LocalControl.isRoutable(id) else { return false }
        let response = try await send(.delete, LocalControl.devicePath(id))
        if response.status == 404 {
            return false
        }
        try Self.expect(200, response)
        return true
    }

    public func send(_ method: HttpMethod, _ path: String, body: Data = Data()) async throws -> LocalControlResponse {
        guard Self.socketExists(socketPath) else { throw LocalControlError.notRunning }
        var request = Data("\(method.rawValue) \(path) HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        request.append(body)
        let raw = try await exchange(request)
        return try Self.parse(raw)
    }

    private func exchange(_ request: Data) async throws -> Data {
        let connection = NWConnection(to: .unix(path: socketPath), using: NWParameters(tls: nil, tcp: NWProtocolTCP.Options()))
        let exchange = LocalExchange(connection: connection, request: request)
        let deadline = Task {
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            exchange.finish(.failure(.timedOut))
        }
        defer { deadline.cancel() }
        return try await exchange.run(on: DispatchQueue(label: "com.joaoalves.mocha.local-client")).get()
    }

    static func socketExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFSOCK
    }

    static func parse(_ raw: Data) throws -> LocalControlResponse {
        let bytes = [UInt8](raw)
        guard let headEnd = bytes.indices.dropLast(3).first(where: { bytes[$0] == 13 && bytes[$0 + 1] == 10 && bytes[$0 + 2] == 13 && bytes[$0 + 3] == 10 }) else {
            throw LocalControlError.invalidResponse
        }
        let head = String(decoding: bytes[..<headEnd], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let statusParts = lines.first?.split(separator: " ", maxSplits: 2) ?? []
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/1."), let status = Int(statusParts[1]) else {
            throw LocalControlError.invalidResponse
        }
        var body = Data(bytes[(headEnd + 4)...])
        let length = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first
        if let length {
            guard body.count >= length else { throw LocalControlError.invalidResponse }
            body = body.prefix(length)
        }
        return LocalControlResponse(status: status, body: body)
    }

    private static func expect(_ status: Int, _ response: LocalControlResponse) throws {
        guard response.status == status else {
            let message = (try? LocalJSON.decoder().decode(LocalErrorBody.self, from: response.body).error)
                ?? String(decoding: response.body, as: UTF8.self)
            throw LocalControlError.unexpectedStatus(response.status, message)
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ response: LocalControlResponse) throws -> Value {
        do {
            return try LocalJSON.decoder().decode(type, from: response.body)
        } catch {
            throw LocalControlError.invalidResponse
        }
    }
}

private final class LocalExchange: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Result<Data, LocalControlError>, Never>?
        var result: Result<Data, LocalControlError>?
        var buffer = Data()
        var connected = false
    }

    private let connection: NWConnection
    private let request: Data
    private let state = Mutex(State())

    init(connection: NWConnection, request: Data) {
        self.connection = connection
        self.request = request
    }

    func run(on queue: DispatchQueue) async -> Result<Data, LocalControlError> {
        await withCheckedContinuation { continuation in
            let early = state.withLock { state -> Result<Data, LocalControlError>? in
                if let result = state.result { return result }
                state.continuation = continuation
                return nil
            }
            if let early {
                continuation.resume(returning: early)
                return
            }
            connection.stateUpdateHandler = { [weak self] connectionState in
                self?.handle(connectionState)
            }
            connection.start(queue: queue)
        }
    }

    func finish(_ result: Result<Data, LocalControlError>) {
        let continuation = state.withLock { state -> CheckedContinuation<Result<Data, LocalControlError>, Never>? in
            guard state.result == nil else { return nil }
            state.result = result
            defer { state.continuation = nil }
            return state.continuation
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(returning: result)
    }

    private func handle(_ connectionState: NWConnection.State) {
        switch connectionState {
        case .ready:
            state.withLock { $0.connected = true }
            connection.send(content: request, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    finish(.failure(.connectionFailed(error.localizedDescription)))
                } else {
                    receive()
                }
            })
        case .waiting(let error), .failed(let error):
            guard !state.withLock({ $0.connected }) else { return }
            finish(.failure(Self.map(error)))
        case .cancelled:
            finish(.failure(.connectionFailed("conexão cancelada")))
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            let buffer = state.withLock { state -> Data in
                if let content { state.buffer.append(content) }
                return state.buffer
            }
            if buffer.count > LocalControlClient.maximumResponseSize {
                finish(.failure(.invalidResponse))
            } else if (try? LocalControlClient.parse(buffer)) != nil {
                finish(.success(buffer))
            } else if let error, buffer.isEmpty {
                finish(.failure(.connectionFailed(error.localizedDescription)))
            } else if isComplete || error != nil {
                finish(.success(buffer))
            } else {
                receive()
            }
        }
    }

    private static func map(_ error: NWError) -> LocalControlError {
        if case .posix(let code) = error, code == .ECONNREFUSED || code == .ENOENT {
            return .notRunning
        }
        return .connectionFailed(error.localizedDescription)
    }
}
