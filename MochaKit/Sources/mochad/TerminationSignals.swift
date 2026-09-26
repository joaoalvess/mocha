import Foundation

final class TerminationSignals {
    private let sources: [any DispatchSourceSignal]
    private let stream: AsyncStream<Int32>

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Int32.self)
        let queue = DispatchQueue(label: "com.joaoalves.mocha.signals")
        self.stream = stream
        self.sources = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { continuation.yield(number) }
            source.resume()
            return source
        }
    }

    func next() async -> Int32 {
        for await number in stream {
            return number
        }
        return 0
    }
}
