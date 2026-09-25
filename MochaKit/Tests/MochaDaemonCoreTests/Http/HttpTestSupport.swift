import Foundation
import Network
import Testing
@testable import MochaDaemonCore

struct TestTimeoutError: Error {}

func withTimeout<T: Sendable>(
    _ timeout: Duration = .seconds(10),
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TestTimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TestTimeoutError() }
        return first
    }
}

final class TestSignal<Value: Sendable>: Sendable {
    private let stream: AsyncStream<Value>
    private let continuation: AsyncStream<Value>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingOldest(1))
        self.stream = stream
        self.continuation = continuation
    }

    func fire(_ value: Value) {
        continuation.yield(value)
    }

    func wait(timeout: Duration = .seconds(10)) async throws -> Value {
        try await withTimeout(timeout) { [stream] in
            for await value in stream {
                return value
            }
            throw TestTimeoutError()
        }
    }
}

extension TestSignal where Value == Void {
    func fire() {
        fire(())
    }
}

func withRunningServer(
    _ router: HttpRouter,
    configuration: HttpServerConfiguration = HttpServerConfiguration(),
    _ body: (UInt16) async throws -> Void
) async throws {
    let server = HttpServer(binding: .loopback(port: 0), router: router, configuration: configuration)
    try await server.start()
    let port = try #require(await server.port)
    do {
        try await body(port)
    } catch {
        await server.stop()
        throw error
    }
    await server.stop()
}

func loopbackEndpoint(_ port: UInt16) throws -> NWEndpoint {
    .hostPort(host: .ipv4(.loopback), port: try #require(NWEndpoint.Port(rawValue: port)))
}

struct TestHttpResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

func makeTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.connectionProxyDictionary = [:]
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
}

func sendRequest(
    _ method: String,
    port: UInt16,
    target: String,
    headers: [String: String] = [:],
    body: Data? = nil
) async throws -> TestHttpResponse {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)\(target)"))
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
    }
    let session = makeTestSession()
    defer { session.invalidateAndCancel() }
    let (data, response) = try await withTimeout(.seconds(30)) { [request] in
        try await session.data(for: request)
    }
    let http = try #require(response as? HTTPURLResponse)
    var fields: [String: String] = [:]
    for (name, value) in http.allHeaderFields {
        if let name = name as? String, let value = value as? String {
            fields[name.lowercased()] = value
        }
    }
    return TestHttpResponse(status: http.statusCode, headers: fields, body: data)
}
