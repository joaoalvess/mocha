public struct UploadResponse: Codable, Sendable, Hashable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}
