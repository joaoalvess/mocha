import CryptoKit
import Foundation

public struct GatewaySpikeEcho: Codable, Sendable, Equatable {
    public let method: String
    public let path: String
    public let query: String?
    public let version: String
    public let headers: [[String]]
    public let bodyBytes: Int
    public let bodySha256: String

    init(_ request: HttpRequest) {
        method = request.method.rawValue
        path = request.path
        query = request.query
        version = request.version
        headers = request.headers.map { [$0.name, $0.value] }
        bodyBytes = request.body.count
        bodySha256 = SHA256.hash(data: request.body).map { String(format: "%02x", $0) }.joined()
    }
}

extension Gateway {
    public static let spikeEchoPath = "/spike/echo"
    public static let spikeMaxBodySize = 20 << 20

    public func addSpikeRoutes(to router: inout HttpRouter) {
        for method in [HttpMethod.get, .post] {
            router.route(method, Self.spikeEchoPath, maxBodySize: Self.spikeMaxBodySize) { request in
                events(.httpRequest(request))
                return try .json(GatewaySpikeEcho(request))
            }
        }
    }
}
