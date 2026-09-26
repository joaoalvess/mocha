import Foundation
import MochaProtocol

public struct HookServer: Sendable {
    public typealias AgentResolver = @Sendable (AgentID) async -> AgentID

    public static let secretHeader = "X-Mocha-Hook-Secret"
    public static let paneHeader = "X-Mocha-Pane"
    public static let maxBodySize = 16 << 20

    let secrets: HookSecretVerifier
    let events: HookEventHub
    let resolveAgent: AgentResolver
    let now: @Sendable () -> Date

    public init(
        secrets: HookSecretVerifier,
        events: HookEventHub,
        resolveAgent: @escaping AgentResolver = { $0 },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.secrets = secrets
        self.events = events
        self.resolveAgent = resolveAgent
        self.now = now
    }

    public func makeRouter() -> HttpRouter {
        var router = HttpRouter()
        for name in HookEventName.allCases {
            router.route(.post, name.path, maxBodySize: Self.maxBodySize) { request in
                await respond(to: request, as: name)
            }
        }
        return router
    }

    func respond(to request: HttpRequest, as name: HookEventName) async -> HttpResponse {
        guard await secrets.accepts(request.headers[Self.secretHeader]) else {
            hooksLogger.warning("\(name.rawValue, privacy: .public) rejected: missing or wrong hook secret")
            return HttpResponse(status: .unauthorized)
        }
        let event: HookEvent
        do {
            event = try HookEvent.decode(name, from: request.body)
        } catch {
            hooksLogger.error("\(name.rawValue, privacy: .public) with an invalid payload: \(String(describing: error), privacy: .public)")
            return HttpResponse(status: .badRequest)
        }
        let pane = request.headers[Self.paneHeader]?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !pane.isEmpty else {
            hooksLogger.debug("\(name.rawValue, privacy: .public) ignored: outside Herdr")
            return Self.noDecision
        }
        let agentId = await resolveAgent(pane)
        hooksLogger.debug("\(name.rawValue, privacy: .public) from \(agentId, privacy: .public), session \(event.context.sessionId, privacy: .public)")
        events.publish(ReceivedHook(agentId: agentId, receivedAt: now(), event: event))
        return Self.noDecision
    }

    static let noDecision = HttpResponse(
        status: .ok,
        headers: ["Content-Type": "application/json"],
        body: Data("{}".utf8)
    )
}
