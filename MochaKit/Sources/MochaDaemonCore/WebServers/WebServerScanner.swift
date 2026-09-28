import Foundation
import MochaProtocol

public protocol WebServerScanning: Sendable {
    func scan() async -> [WebServer]
}

public struct WebServerScanner: WebServerScanning {
    public struct Configuration: Sendable {
        public var excludedPorts: Set<Int>
        public var probeTimeout: Duration
        public var deadline: Duration
        public var isExcludedExecutable: @Sendable (String) -> Bool

        public init(
            excludedPorts: Set<Int>,
            probeTimeout: Duration = .milliseconds(800),
            deadline: Duration = .seconds(2),
            isExcludedExecutable: @escaping @Sendable (String) -> Bool = WebServerScanner.isSystemExecutable
        ) {
            self.excludedPorts = excludedPorts
            self.probeTimeout = probeTimeout
            self.deadline = deadline
            self.isExcludedExecutable = isExcludedExecutable
        }
    }

    struct Candidate: Sendable, Equatable {
        let pid: Int
        let process: String
        let port: Int
        let directory: String?
    }

    private let processes: any ProcessListing
    private let probe: any WebPageProbing
    private let configuration: Configuration

    public init(
        configuration: Configuration,
        processes: any ProcessListing = LibprocProcessListing(),
        probe: any WebPageProbing = URLSessionWebPageProbe()
    ) {
        self.configuration = configuration
        self.processes = processes
        self.probe = probe
    }

    public func scan() async -> [WebServer] {
        let clock = ContinuousClock()
        let start = clock.now
        let candidates = Self.candidates(from: await processes.listeningProcesses(), configuration: configuration)
        let remaining = configuration.deadline - (clock.now - start)
        let timeout = min(configuration.probeTimeout, max(remaining, .zero))
        let pages = await probeAll(candidates.map(\.port), timeout: timeout)
        return candidates.compactMap { candidate in
            guard let page = pages[candidate.port] else { return nil }
            return WebServer(
                pid: candidate.pid,
                process: candidate.process,
                port: candidate.port,
                title: HTMLTitle.extract(from: page),
                directory: candidate.directory
            )
        }
    }

    public static func isSystemExecutable(_ path: String) -> Bool {
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") { return true }
        let applications = "/Applications/"
        guard path.hasPrefix(applications) else { return false }
        let rest = path.dropFirst(applications.count)
        guard let slash = rest.firstIndex(of: "/") else { return false }
        return rest[..<slash].hasSuffix(".app")
    }

    static func candidates(from processes: [ListeningProcess], configuration: Configuration) -> [Candidate] {
        var byPort: [Int: Candidate] = [:]
        for process in processes {
            if let path = process.executablePath, configuration.isExcludedExecutable(path) { continue }
            for port in process.ports where !configuration.excludedPorts.contains(port) {
                if let existing = byPort[port], existing.pid <= process.pid { continue }
                byPort[port] = Candidate(pid: process.pid, process: process.name, port: port, directory: process.directory)
            }
        }
        return byPort.values.sorted { $0.port < $1.port }
    }

    private func probeAll(_ ports: [Int], timeout: Duration) async -> [Int: Data] {
        guard timeout > .zero else { return [:] }
        let probe = probe
        return await withTaskGroup(of: (Int, Data?).self) { group in
            for port in ports {
                group.addTask {
                    (port, await Self.page(on: port, using: probe, timeout: timeout))
                }
            }
            var pages: [Int: Data] = [:]
            for await (port, page) in group {
                if let page {
                    pages[port] = page
                }
            }
            return pages
        }
    }

    private static func page(on port: Int, using probe: any WebPageProbing, timeout: Duration) async -> Data? {
        await withTaskGroup(of: WebPageProbeResult?.self) { group in
            group.addTask {
                await probe.probe(port: port, timeout: timeout)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            guard case .html(let data) = first else { return nil }
            return data
        }
    }
}
