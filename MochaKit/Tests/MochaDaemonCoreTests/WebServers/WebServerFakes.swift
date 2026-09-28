import Foundation
import MochaProtocol
import Synchronization
@testable import MochaDaemonCore

struct FakeProcessListing: ProcessListing {
    var processes: [ListeningProcess]
    var delay: Duration = .zero

    func listeningProcesses() async -> [ListeningProcess] {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return processes
    }
}

final class FakeWebPageProbe: WebPageProbing {
    enum Behavior: Sendable {
        case respond(WebPageProbeResult)
        case hang
    }

    private let behaviors: [Int: Behavior]
    private let probedPorts = Mutex<[Int]>([])

    init(_ behaviors: [Int: Behavior]) {
        self.behaviors = behaviors
    }

    var probed: [Int] {
        probedPorts.withLock { $0.sorted() }
    }

    func probe(port: Int, timeout: Duration) async -> WebPageProbeResult {
        probedPorts.withLock { $0.append(port) }
        switch behaviors[port] ?? .respond(.unreachable) {
        case .respond(let result):
            return result
        case .hang:
            try? await Task.sleep(for: .seconds(30))
            return .html(Data("<title>Tarde demais</title>".utf8))
        }
    }
}

struct FakeWebServerScanner: WebServerScanning {
    var servers: [WebServer]

    func scan() async -> [WebServer] {
        servers
    }
}

extension WebPageProbeResult {
    static func page(_ html: String) -> WebPageProbeResult {
        .html(Data(html.utf8))
    }
}
