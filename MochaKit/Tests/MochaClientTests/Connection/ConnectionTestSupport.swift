import Foundation
import MochaProtocol
import Synchronization
import Testing
@testable import MochaClient

struct TestTimeoutError: Error {}

func waitUntil(
    timeout: Duration = .seconds(10),
    _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw TestTimeoutError() }
        try await Task.sleep(for: .milliseconds(2))
    }
}

final class ManualClock: ConnectionClock {
    private struct Sleeper {
        let id: Int
        let duration: Duration
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Duration = .zero
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var nextId = 0
        var requested: [Duration] = []
    }

    private let state = Mutex(State())

    var now: Duration {
        state.withLock { $0.now }
    }

    var requestedSleeps: [Duration] {
        state.withLock { $0.requested }
    }

    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    var pendingSleeps: [Duration] {
        state.withLock { $0.sleepers.map(\.duration) }
    }

    func sleep(for duration: Duration) async throws {
        let id = state.withLock { state in
            state.nextId += 1
            state.requested.append(duration)
            return state.nextId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    if state.cancelled.remove(id) != nil {
                        return .failure(CancellationError())
                    }
                    state.sleepers.append(Sleeper(id: id, duration: duration, deadline: state.now + duration, continuation: continuation))
                    return nil
                }
                if let outcome {
                    continuation.resume(with: outcome)
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    func waitForSleepers(_ count: Int = 1) async throws {
        try await waitUntil { self.sleeperCount >= count }
    }
}

final class ScaledClock: ConnectionClock {
    let factor: Double
    private let origin = ContinuousClock.now
    private let requested = Mutex<[Duration]>([])

    init(factor: Double) {
        self.factor = factor
    }

    var now: Duration {
        (ContinuousClock.now - origin) * factor
    }

    var requestedSleeps: [Duration] {
        requested.withLock { $0 }
    }

    func sleep(for duration: Duration) async throws {
        requested.withLock { $0.append(duration) }
        try await Task.sleep(for: duration / factor)
    }
}

struct FakeChannelError: Error, Equatable {
    let failure: WebSocketChannelFailure
}

final class FakeChannel: WebSocketChannel {
    private struct State {
        var queue: [Result<String, FakeChannelError>] = []
        var waiter: CheckedContinuation<String?, any Error>?
        var sent: [String] = []
        var pings: [Duration] = []
        var closeCode: URLSessionWebSocketTask.CloseCode?
        var closedAt: Duration?
    }

    let url: URL
    private let clock: any ConnectionClock
    private let answersPings: Bool
    private let state = Mutex(State())
    private let encoder = JSONEncoder()

    init(url: URL, clock: any ConnectionClock, answersPings: Bool) {
        self.url = url
        self.clock = clock
        self.answersPings = answersPings
    }

    var sentEnvelopes: [ClientEnvelope] {
        state.withLock { $0.sent }.compactMap { try? JSONDecoder().decode(ClientEnvelope.self, from: Data($0.utf8)) }
    }

    var pingTimes: [Duration] {
        state.withLock { $0.pings }
    }

    var closeCode: URLSessionWebSocketTask.CloseCode? {
        state.withLock { $0.closeCode }
    }

    var closedAt: Duration? {
        state.withLock { $0.closedAt }
    }

    var hello: HelloPayload? {
        guard case .hello(let hello) = sentEnvelopes.first?.message else { return nil }
        return hello
    }

    func send(_ text: String) async throws {
        let isClosed = state.withLock { state in
            guard state.closeCode == nil else { return true }
            state.sent.append(text)
            return false
        }
        if isClosed {
            throw FakeChannelError(failure: .network)
        }
    }

    func receive() async throws -> String? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, any Error>) in
                let next = state.withLock { state -> Result<String, FakeChannelError>? in
                    if !state.queue.isEmpty {
                        return state.queue.removeFirst()
                    }
                    if state.closeCode != nil {
                        return .failure(FakeChannelError(failure: .network))
                    }
                    state.waiter = continuation
                    return nil
                }
                switch next {
                case .success(let text)?: continuation.resume(returning: text)
                case .failure(let error)?: continuation.resume(throwing: error)
                case nil: break
                }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    func sendPing(_ pongReceived: @escaping @Sendable (Bool) -> Void) {
        state.withLock { $0.pings.append(clock.now) }
        if answersPings {
            pongReceived(true)
        }
    }

    func close(_ code: URLSessionWebSocketTask.CloseCode) {
        let waiter = state.withLock { state in
            defer { state.waiter = nil }
            if state.closeCode == nil {
                state.closeCode = code
                state.closedAt = clock.now
            }
            return state.waiter
        }
        waiter?.resume(throwing: FakeChannelError(failure: .network))
    }

    func failure(for error: any Error) -> WebSocketChannelFailure {
        (error as? FakeChannelError)?.failure ?? .network
    }

    func deliver(_ message: ServerMessage, id: String? = nil) throws {
        let data = try encoder.encode(ServerEnvelope(id: id, message: message))
        push(.success(String(decoding: data, as: UTF8.self)))
    }

    func fail(_ failure: WebSocketChannelFailure) {
        push(.failure(FakeChannelError(failure: failure)))
    }

    private func push(_ item: Result<String, FakeChannelError>) {
        let waiter = state.withLock { state in
            guard let waiter = state.waiter else {
                state.queue.append(item)
                return CheckedContinuation<String?, any Error>?.none
            }
            state.waiter = nil
            return waiter
        }
        switch item {
        case .success(let text): waiter?.resume(returning: text)
        case .failure(let error): waiter?.resume(throwing: error)
        }
    }
}

final class FakeTransport: WebSocketTransport {
    private let clock: any ConnectionClock
    private let answersPings: Bool
    private let channels = Mutex<[FakeChannel]>([])

    init(clock: any ConnectionClock, answersPings: Bool = true) {
        self.clock = clock
        self.answersPings = answersPings
    }

    var channelCount: Int {
        channels.withLock { $0.count }
    }

    func connect(to url: URL) -> any WebSocketChannel {
        let channel = FakeChannel(url: url, clock: clock, answersPings: answersPings)
        channels.withLock { $0.append(channel) }
        return channel
    }

    func channel(_ index: Int) async throws -> FakeChannel {
        try await waitUntil { self.channelCount > index }
        return channels.withLock { $0[index] }
    }
}

actor FakeTokenStore: TokenStore {
    private(set) var credential: DeviceCredential?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    init(credential: DeviceCredential? = nil) {
        self.credential = credential
    }

    func load() -> DeviceCredential? {
        credential
    }

    func save(_ credential: DeviceCredential) {
        self.credential = credential
        saveCount += 1
    }

    func delete() {
        credential = nil
        deleteCount += 1
    }
}

final class FakePathMonitor: NetworkPathMonitoring {
    private let continuations = Mutex<[AsyncStream<NetworkPathUpdate>.Continuation]>([])

    func updates() -> AsyncStream<NetworkPathUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: NetworkPathUpdate.self)
        continuations.withLock { $0.append(continuation) }
        return stream
    }

    var subscriberCount: Int {
        continuations.withLock { $0.count }
    }

    func send(_ update: NetworkPathUpdate) {
        for continuation in continuations.withLock({ $0 }) {
            continuation.yield(update)
        }
    }
}

final class Recorder<Element: Sendable>: Sendable {
    private final class Storage: Sendable {
        let values = Mutex<[Element]>([])
    }

    private let storage: Storage
    private let task: Task<Void, Never>

    init(_ stream: AsyncStream<Element>) {
        let storage = Storage()
        self.storage = storage
        task = Task {
            for await value in stream {
                storage.values.withLock { $0.append(value) }
            }
        }
    }

    deinit {
        task.cancel()
    }

    var all: [Element] {
        storage.values.withLock { $0 }
    }

    var last: Element? {
        storage.values.withLock { $0.last }
    }
}

extension Recorder where Element == ConnectionState {
    func wait(for state: ConnectionState, timeout: Duration = .seconds(10)) async throws {
        try await waitUntil(timeout: timeout) { self.last == state }
    }
}

enum ConnectionFixtures {
    static let url = URL(string: "wss://mac-mini.tail1234.ts.net/v1")!
    static let credential = DeviceCredential(url: url, token: "stored-token")
    static let link = PairingLink(url: url, code: "abc-DEF_123")
    static let configuration = ConnectionConfiguration(deviceName: "iPhone", appVersion: "0.1.0")
    static let host = HostInfo(hostName: "MacBook-Pro", daemonVersion: "0.1.0", herdrConnected: true)

    static func helloOk(token: String? = nil) -> ServerMessage {
        .helloOk(HelloOkPayload(host: host, deviceId: "device-1", deviceToken: token, preferences: DevicePreferences()))
    }
}
