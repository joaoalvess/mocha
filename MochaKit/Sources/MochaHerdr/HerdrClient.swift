import Foundation
import Synchronization

public struct HerdrClientConfiguration: Sendable {
    public var socketPath: String
    public var requestTimeout: Duration
    public var promptTimeout: Duration
    public var waitMargin: Duration

    public init(
        socketPath: String = HerdrSocketPath.resolve(),
        requestTimeout: Duration = .seconds(5),
        promptTimeout: Duration = .seconds(10),
        waitMargin: Duration = .seconds(2)
    ) {
        self.socketPath = socketPath
        self.requestTimeout = requestTimeout
        self.promptTimeout = promptTimeout
        self.waitMargin = waitMargin
    }

    public func waitTimeout(for timeout: Duration) -> Duration {
        timeout + waitMargin
    }
}

public struct HerdrClient: Sendable {
    public let configuration: HerdrClientConfiguration

    private let identifiers = RequestIdentifiers()
    private let queue = DispatchQueue(label: "com.joaoalves.mocha.herdr")

    public init(configuration: HerdrClientConfiguration = HerdrClientConfiguration()) {
        self.configuration = configuration
    }

    public func ping() async throws -> HerdrPong {
        try await perform(.ping, expecting: "pong", as: HerdrPong.self)
    }

    public func sessionSnapshot() async throws -> HerdrSessionSnapshot {
        try await perform(.sessionSnapshot, expecting: "session_snapshot", as: HerdrResponse.Snapshot.self).snapshot
    }

    public func agentList() async throws -> [HerdrPane] {
        try await perform(.agentList, expecting: "agent_list", as: HerdrResponse.AgentList.self).agents
    }

    public func agentGet(target: String) async throws -> HerdrPane {
        try await perform(.agentGet(target: target), expecting: "agent_info", as: HerdrResponse.Agent.self).agent
    }

    public func workspaceList() async throws -> [HerdrWorkspace] {
        try await perform(.workspaceList, expecting: "workspace_list", as: HerdrResponse.WorkspaceList.self).workspaces
    }

    public func tabList(workspaceId: String? = nil) async throws -> [HerdrTab] {
        try await perform(.tabList(workspaceId: workspaceId), expecting: "tab_list", as: HerdrResponse.TabList.self).tabs
    }

    public func paneGet(paneId: String) async throws -> HerdrPane {
        try await perform(.paneGet(paneId: paneId), expecting: "pane_info", as: HerdrResponse.Pane.self).pane
    }

    public func paneRead(paneId: String, source: HerdrReadSource = .visible, lines: Int? = nil) async throws -> HerdrPaneRead {
        try await perform(.paneRead(paneId: paneId, source: source, lines: lines), expecting: "pane_read", as: HerdrResponse.Read.self).read
    }

    @discardableResult
    public func agentPrompt(target: String, text: String) async throws -> HerdrPane {
        try await perform(
            .agentPrompt(target: target, text: text),
            expecting: "agent_prompted",
            as: HerdrResponse.Agent.self,
            timeout: configuration.promptTimeout
        ).agent
    }

    public func agentSendKeys(target: String, keys: [String]) async throws {
        _ = try await perform(.agentSendKeys(target: target, keys: keys), expecting: "ok", as: HerdrResponse.Empty.self)
    }

    public func tabCreate(workspaceId: String, cwd: String?) async throws -> HerdrTabCreated {
        try await perform(.tabCreate(workspaceId: workspaceId, cwd: cwd), expecting: "tab_created", as: HerdrTabCreated.self)
    }

    @discardableResult
    public func agentStart(
        name: String,
        kind: String,
        paneId: String,
        args: [String],
        timeout: Duration? = nil
    ) async throws -> HerdrAgentStarted {
        try await perform(
            .agentStart(name: name, kind: kind, paneId: paneId, args: args, timeoutMs: timeout?.herdrMilliseconds),
            expecting: "agent_started",
            as: HerdrAgentStarted.self,
            timeout: timeout.map(configuration.waitTimeout(for:))
        )
    }

    public func agentWait(target: String, until statuses: [HerdrAgentStatus], timeout: Duration) async throws -> HerdrPane {
        try await perform(
            .agentWait(target: target, until: statuses, timeoutMs: timeout.herdrMilliseconds),
            expecting: "agent_info",
            as: HerdrResponse.Agent.self,
            timeout: configuration.waitTimeout(for: timeout)
        ).agent
    }

    public func subscribe(_ subscriptions: [HerdrSubscription]) async throws -> HerdrEventSubscription {
        let request = HerdrRequest.eventsSubscribe(subscriptions)
        let method = request.method
        let line = try request.encodedLine(id: identifiers.next())
        let path = configuration.socketPath
        let queue = self.queue
        let connection = try await Self.withDeadline(configuration.requestTimeout, method: method) {
            let connection = try await HerdrSocketConnection.open(path: path, queue: queue)
            do {
                try await connection.write(line)
                guard let ack = await connection.readLine() else {
                    throw HerdrClientError.closedWithoutResponse(method: method)
                }
                _ = try HerdrResponse.decode(ack, method: method, expecting: "subscription_started", as: HerdrResponse.Empty.self)
                return connection
            } catch {
                connection.close()
                throw error
            }
        }
        return HerdrEventSubscription(connection: connection)
    }

    private func perform<Result: Decodable & Sendable>(
        _ request: HerdrRequest,
        expecting type: String,
        as resultType: Result.Type,
        timeout: Duration? = nil
    ) async throws -> Result {
        let method = request.method
        let line = try request.encodedLine(id: identifiers.next())
        let path = configuration.socketPath
        let queue = self.queue
        let response = try await Self.withDeadline(timeout ?? configuration.requestTimeout, method: method) {
            let connection = try await HerdrSocketConnection.open(path: path, queue: queue)
            defer { connection.close() }
            try await connection.write(line)
            guard let response = await connection.readLine() else {
                throw HerdrClientError.closedWithoutResponse(method: method)
            }
            return response
        }
        return try HerdrResponse.decode(response, method: method, expecting: type, as: resultType)
    }

    private static func withDeadline<Value: Sendable>(
        _ duration: Duration,
        method: String,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: duration)
                throw HerdrClientError.timeout(method: method)
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw HerdrClientError.timeout(method: method)
            }
            return value
        }
    }
}

extension Duration {
    var herdrMilliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

private final class RequestIdentifiers: Sendable {
    private let counter = Mutex(0)

    func next() -> String {
        let value = counter.withLock { counter in
            counter += 1
            return counter
        }
        return "mocha-\(value)"
    }
}
