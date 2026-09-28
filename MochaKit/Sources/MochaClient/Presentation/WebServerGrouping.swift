import MochaProtocol

public struct WebServerGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let servers: [WebServer]

    public init(id: String, title: String, servers: [WebServer]) {
        self.id = id
        self.title = title
        self.servers = servers
    }
}

public enum WebServerGrouping {
    public static let unassignedGroupId = "host"

    public static func groups(
        servers: [WebServer],
        host: String,
        workspaces: [WorkspaceNode],
        scope: WorkspaceID? = nil
    ) -> [WebServerGroup] {
        let sorted = servers.sorted { $0.port < $1.port }
        let ordered = workspaces.flattenedWorkspaces
        if let scope {
            let title = ordered.first { $0.id == scope }?.label ?? host
            return [WebServerGroup(id: scope, title: title, servers: sorted.filter { $0.workspaceId == scope })]
        }
        let known = Set(ordered.map(\.id))
        var groups = ordered.compactMap { workspace -> WebServerGroup? in
            let owned = sorted.filter { $0.workspaceId == workspace.id }
            return owned.isEmpty ? nil : WebServerGroup(id: workspace.id, title: workspace.label, servers: owned)
        }
        let unassigned = sorted.filter { server in server.workspaceId.map { !known.contains($0) } ?? true }
        if !unassigned.isEmpty {
            groups.append(WebServerGroup(id: unassignedGroupId, title: host, servers: unassigned))
        }
        return groups
    }
}
