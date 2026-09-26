import Network

public enum HttpBinding: Sendable, Equatable, CustomStringConvertible {
    case loopback(port: UInt16)
    case unixSocket(path: String)

    public var description: String {
        switch self {
        case .loopback(let port): "127.0.0.1:\(port)"
        case .unixSocket(let path): "unix:\(path)"
        }
    }
}

public struct HttpServerConfiguration: Sendable {
    public var defaultMaxBodySize: Int
    public var maxHeadSize: Int
    public var headReadTimeout: Duration
    public var maxDrainSize: Int
    public var drainTimeout: Duration

    public init(
        defaultMaxBodySize: Int = 1 << 20,
        maxHeadSize: Int = 32 << 10,
        headReadTimeout: Duration = .seconds(30),
        maxDrainSize: Int = 32 << 20,
        drainTimeout: Duration = .seconds(10)
    ) {
        self.defaultMaxBodySize = defaultMaxBodySize
        self.maxHeadSize = maxHeadSize
        self.headReadTimeout = headReadTimeout
        self.maxDrainSize = maxDrainSize
        self.drainTimeout = drainTimeout
    }
}

public enum HttpServerError: Error, Sendable, Equatable {
    case alreadyStarted
    case listenerFailed(NWError)
    case socketPathTooLong(String)
    case socketPathOccupied(String)
    case socketPermissionsFailed(Int32)
}
