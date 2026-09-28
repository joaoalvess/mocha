public struct ListeningProcess: Sendable, Equatable {
    public var pid: Int
    public var name: String
    public var executablePath: String?
    public var directory: String?
    public var ports: [Int]

    public init(pid: Int, name: String, executablePath: String? = nil, directory: String? = nil, ports: [Int]) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.directory = directory
        self.ports = ports
    }
}

public protocol ProcessListing: Sendable {
    func listeningProcesses() async -> [ListeningProcess]
}
