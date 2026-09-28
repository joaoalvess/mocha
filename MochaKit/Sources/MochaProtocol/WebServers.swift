public struct WebServer: Codable, Sendable, Hashable {
    public var pid: Int
    public var process: String
    public var port: Int
    public var title: String?
    public var directory: String?
    public var workspaceId: WorkspaceID?

    public init(pid: Int, process: String, port: Int, title: String? = nil, directory: String? = nil, workspaceId: WorkspaceID? = nil) {
        self.pid = pid
        self.process = process
        self.port = port
        self.title = title
        self.directory = directory
        self.workspaceId = workspaceId
    }
}
