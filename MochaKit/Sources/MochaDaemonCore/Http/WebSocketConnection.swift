import Foundation

public struct WebSocketOptions: Sendable {
    public var maxMessageSize: Int
    public var closeTimeout: Duration

    public init(maxMessageSize: Int = 1 << 20, closeTimeout: Duration = .seconds(5)) {
        self.maxMessageSize = maxMessageSize
        self.closeTimeout = closeTimeout
    }
}

public enum WebSocketError: Error, Sendable, Equatable {
    case notOpen
    case sendFailed
}

public actor WebSocketConnection {
    private enum State {
        case open
        case closeSent
        case failing
        case closed
    }

    private static let receiveChunkSize = 64 * 1024

    public nonisolated let messages: AsyncStream<WebSocketMessage>
    public private(set) var closeCode: WebSocketCloseCode?
    public private(set) var closeReason: String?

    private let messageContinuation: AsyncStream<WebSocketMessage>.Continuation
    private let io: ConnectionIO
    private let options: WebSocketOptions
    private var buffer: [UInt8]
    private var fragmentOpcode: WebSocketOpcode?
    private var fragmentPayload: [UInt8] = []
    private var state = State.open
    private var closeDeadline: Task<Void, Never>?

    init(io: ConnectionIO, options: WebSocketOptions, bufferedBytes: [UInt8]) {
        let (messages, continuation) = AsyncStream.makeStream(of: WebSocketMessage.self)
        self.messages = messages
        self.messageContinuation = continuation
        self.io = io
        self.options = options
        self.buffer = bufferedBytes
    }

    public var isOpen: Bool {
        state == .open
    }

    public func send(text: String) async throws {
        try await sendDataFrame(.text, payload: Data(text.utf8))
    }

    public func send(binary: Data) async throws {
        try await sendDataFrame(.binary, payload: binary)
    }

    public func close(code: WebSocketCloseCode = .normalClosure, reason: String = "") async {
        guard state == .open else { return }
        state = .closeSent
        messageContinuation.finish()
        _ = await write(WebSocketFrame.encode(.close, payload: WebSocketFrame.closePayload(code: code, reason: reason)))
        armCloseDeadline()
    }

    func run() async {
        await processBuffer()
        while state != .closed {
            let chunk = await io.receive(maximumLength: Self.receiveChunkSize)
            if state == .open || state == .closeSent {
                buffer.append(contentsOf: chunk.bytes)
                await processBuffer()
            }
            if chunk.isEnd { break }
        }
        terminate()
    }

    private func processBuffer() async {
        var offset = 0
        while state == .open || state == .closeSent {
            let decoding = WebSocketFrame.decode(
                buffer,
                from: offset,
                maxDataPayload: options.maxMessageSize - fragmentPayload.count
            )
            switch decoding {
            case .incomplete:
                buffer.removeFirst(offset)
                return
            case .violation(let code):
                await fail(code)
            case .frame(let frame, let consumed):
                offset += consumed
                await handle(frame)
            }
        }
        buffer.removeAll()
    }

    private func handle(_ frame: WebSocketFrame) async {
        switch frame.opcode {
        case .text, .binary:
            guard fragmentOpcode == nil else { return await fail(.protocolError) }
            if frame.isFinal {
                await deliver(frame.opcode, frame.payload)
            } else {
                fragmentOpcode = frame.opcode
                fragmentPayload = frame.payload
            }
        case .continuation:
            guard let opcode = fragmentOpcode else { return await fail(.protocolError) }
            fragmentPayload.append(contentsOf: frame.payload)
            guard frame.isFinal else { return }
            let payload = fragmentPayload
            fragmentOpcode = nil
            fragmentPayload = []
            await deliver(opcode, payload)
        case .ping:
            guard state == .open else { return }
            _ = await write(WebSocketFrame.encode(.pong, payload: frame.payload))
        case .pong:
            return
        case .close:
            await receiveClose(frame.payload)
        }
    }

    private func deliver(_ opcode: WebSocketOpcode, _ payload: [UInt8]) async {
        guard state == .open else { return }
        if opcode == .text {
            guard let text = String(validating: payload, as: UTF8.self) else { return await fail(.invalidPayload) }
            messageContinuation.yield(.text(text))
        } else {
            messageContinuation.yield(.binary(Data(payload)))
        }
    }

    private func receiveClose(_ payload: [UInt8]) async {
        switch WebSocketFrame.parseClose(payload) {
        case .invalid(let code):
            await fail(code)
        case .valid(let code, let reason):
            closeCode = code
            closeReason = reason
            switch state {
            case .open:
                state = .closed
                messageContinuation.finish()
                let echo = code.map { WebSocketFrame.closePayload(code: $0, reason: "") } ?? []
                _ = await write(WebSocketFrame.encode(.close, payload: echo), closingWrite: true)
            case .closeSent:
                state = .closed
            case .failing, .closed:
                return
            }
            httpLogger.debug("websocket closed by peer with code \(code?.rawValue ?? 0, privacy: .public)")
        }
    }

    private func fail(_ code: WebSocketCloseCode) async {
        switch state {
        case .open:
            state = .failing
            messageContinuation.finish()
            httpLogger.notice("websocket failed with code \(code.rawValue, privacy: .public)")
            let frame = WebSocketFrame.encode(.close, payload: WebSocketFrame.closePayload(code: code, reason: ""))
            _ = await write(frame, closingWrite: true)
            armCloseDeadline()
        case .closeSent:
            state = .closed
        case .failing, .closed:
            return
        }
    }

    private func sendDataFrame(_ opcode: WebSocketOpcode, payload: Data) async throws {
        guard state == .open else { throw WebSocketError.notOpen }
        guard await write(WebSocketFrame.encode(opcode, payload: payload)) else { throw WebSocketError.sendFailed }
    }

    private func write(_ frame: Data, closingWrite: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            io.enqueue(frame, closingWrite: closingWrite) { continuation.resume(returning: $0) }
        }
    }

    private func armCloseDeadline() {
        closeDeadline?.cancel()
        closeDeadline = io.scheduleCancellation(after: options.closeTimeout)
    }

    private func terminate() {
        state = .closed
        messageContinuation.finish()
        closeDeadline?.cancel()
        closeDeadline = nil
        io.cancel()
    }
}
