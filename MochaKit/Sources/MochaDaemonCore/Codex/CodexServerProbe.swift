import Foundation
import Synchronization

public struct CodexServerInfo: Sendable, Equatable {
    public let version: String?
    public let signedIn: Bool?
    public let plan: String?

    public init(version: String?, signedIn: Bool?, plan: String?) {
        self.version = version
        self.signedIn = signedIn
        self.plan = plan
    }
}

public enum CodexServerProbe: Sendable, Equatable {
    case missingSocket(String)
    case failed(String)
    case reachable(CodexServerInfo)
}

extension CodexInspector {
    private final class Reply: Sendable {
        private let pending: Mutex<CheckedContinuation<CodexServerProbe, Never>?>

        init(_ continuation: CheckedContinuation<CodexServerProbe, Never>) {
            pending = Mutex(continuation)
        }

        func resume(_ probe: CodexServerProbe) {
            pending.withLock { continuation in
                continuation?.resume(returning: probe)
                continuation = nil
            }
        }
    }

    public static func appServer(at socketPath: String, timeout: Duration = .seconds(5)) async -> CodexServerProbe {
        guard FileManager.default.fileExists(atPath: socketPath) else { return .missingSocket(socketPath) }
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            return .failed("caminho do socket longo demais: \(socketPath)")
        }
        let server = CodexAppServer(socketPath: socketPath, requestTimeout: timeout)
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<CodexServerProbe, Never>) in
            let reply = Reply(continuation)
            Task { reply.resume(await probe(server)) }
            Task {
                try? await Task.sleep(for: timeout)
                reply.resume(.failed("sem resposta ao initialize em \(timeout.components.seconds) s"))
            }
        }
        await server.shutdown()
        return result
    }

    static func version(fromUserAgent userAgent: String?) -> String? {
        guard let product = userAgent?.split(separator: " ").first, let slash = product.firstIndex(of: "/") else { return nil }
        let version = product[product.index(after: slash)...]
        return version.isEmpty ? nil : String(version)
    }

    private static func probe(_ server: CodexAppServer) async -> CodexServerProbe {
        let initialize: OrderedJSON
        do {
            initialize = try await server.connect()
        } catch CodexAppServerError.rejected(let message) {
            return .failed("o initialize foi recusado: \(message)")
        } catch {
            return .failed("o initialize falhou: \(String(describing: error))")
        }
        let account = try? await server.request("account/read", params: .object([]))
        return .reachable(CodexServerInfo(
            version: version(fromUserAgent: initialize["userAgent"]?.stringValue),
            signedIn: account.map { $0["account"]?.members != nil },
            plan: account?["account"]?["planType"]?.stringValue
        ))
    }
}
