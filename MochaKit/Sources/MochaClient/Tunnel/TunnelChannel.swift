import Foundation

public protocol TunnelChannelInbound: Sendable {
    func forEachChunk(_ body: @Sendable (Data) async throws -> Void) async throws
}

public protocol TunnelChannelOutbound: Sendable {
    func write(_ data: Data) async throws
    func finish()
}

public protocol TunnelChannel: Sendable {
    func exchange(_ body: @Sendable (any TunnelChannelInbound, any TunnelChannelOutbound) async throws -> Void) async throws
}

public typealias TunnelChannelOpener = @Sendable (Int) async throws -> any TunnelChannel

public struct AsyncStreamTunnelInbound: TunnelChannelInbound {
    private let stream: AsyncThrowingStream<Data, any Error>

    public init(_ stream: AsyncThrowingStream<Data, any Error>) {
        self.stream = stream
    }

    public func forEachChunk(_ body: @Sendable (Data) async throws -> Void) async throws {
        for try await chunk in stream {
            try await body(chunk)
        }
    }
}

public struct AsyncStreamTunnelOutbound: TunnelChannelOutbound {
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation

    public init(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.continuation = continuation
    }

    public func write(_ data: Data) async throws {
        continuation.yield(data)
    }

    public func finish() {
        continuation.finish()
    }
}
