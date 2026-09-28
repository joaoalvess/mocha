import Foundation
import MochaProtocol

public struct WorkspaceRoot: Sendable, Equatable {
    public var workspaceId: WorkspaceID
    public var path: String
    public var isCheckout: Bool

    public init(workspaceId: WorkspaceID, path: String, isCheckout: Bool) {
        self.workspaceId = workspaceId
        self.path = path
        self.isCheckout = isCheckout
    }

    public static func assign(
        _ servers: [WebServer],
        to roots: [WorkspaceRoot],
        excludedPaths: Set<String> = ["/", NSHomeDirectory()]
    ) -> [WebServer] {
        let usable = roots
            .map { WorkspaceRoot(workspaceId: $0.workspaceId, path: normalized($0.path), isCheckout: $0.isCheckout) }
            .filter { !excludedPaths.map(normalized).contains($0.path) }
        return servers.map { server in
            var server = server
            server.workspaceId = server.directory.flatMap { owner(of: normalized($0), in: usable) }
            return server
        }
    }

    static func owner(of directory: String, in roots: [WorkspaceRoot]) -> WorkspaceID? {
        roots
            .filter { directory == $0.path || directory.hasPrefix($0.path + "/") }
            .max { ($0.path.count, $0.isCheckout ? 1 : 0) < ($1.path.count, $1.isCheckout ? 1 : 0) }?
            .workspaceId
    }

    static func normalized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }
}
