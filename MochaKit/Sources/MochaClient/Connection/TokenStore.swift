import Foundation

public struct DeviceCredential: Codable, Sendable, Equatable {
    public var url: URL
    public var token: String

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }
}

public protocol TokenStore: Sendable {
    func load() async throws -> DeviceCredential?
    func save(_ credential: DeviceCredential) async throws
    func delete() async throws
}
