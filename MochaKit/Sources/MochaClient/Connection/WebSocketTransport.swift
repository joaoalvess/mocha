import Foundation

public enum WebSocketChannelFailure: Sendable, Equatable {
    case handshake(status: Int)
    case closed(code: Int)
    case network
}

public protocol WebSocketChannel: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String?
    func sendPing(_ pongReceived: @escaping @Sendable (Bool) -> Void)
    func close(_ code: URLSessionWebSocketTask.CloseCode)
    func failure(for error: any Error) -> WebSocketChannelFailure
}

public protocol WebSocketTransport: Sendable {
    func connect(to url: URL) -> any WebSocketChannel
}

public final class URLSessionWebSocketTransport: WebSocketTransport {
    public static let handshakeTimeout: TimeInterval = 15
    public static let maximumMessageSize = 16 << 20

    private let session: URLSession

    public init(handshakeTimeout: TimeInterval = URLSessionWebSocketTransport.handshakeTimeout) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = handshakeTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func connect(to url: URL) -> any WebSocketChannel {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = Self.maximumMessageSize
        task.resume()
        return URLSessionWebSocketChannel(task: task)
    }
}

final class URLSessionWebSocketChannel: WebSocketChannel {
    private static let switchingProtocols = 101

    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String? {
        switch try await task.receive() {
        case .string(let text): text
        case .data: nil
        @unknown default: nil
        }
    }

    func sendPing(_ pongReceived: @escaping @Sendable (Bool) -> Void) {
        task.sendPing { error in
            pongReceived(error == nil)
        }
    }

    func close(_ code: URLSessionWebSocketTask.CloseCode) {
        task.cancel(with: code, reason: nil)
    }

    func failure(for error: any Error) -> WebSocketChannelFailure {
        if let response = task.response as? HTTPURLResponse, response.statusCode != Self.switchingProtocols {
            return .handshake(status: response.statusCode)
        }
        if task.closeCode != .invalid {
            return .closed(code: task.closeCode.rawValue)
        }
        return .network
    }
}
