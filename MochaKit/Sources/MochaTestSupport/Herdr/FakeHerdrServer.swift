import Foundation
import Network

public struct FakeHerdrRequest: Sendable {
    public let id: String
    public let method: String
    public let line: Data
    public let params: Data

    public func stringParam(_ key: String) -> String? {
        paramsObject?[key] as? String
    }

    public func stringArrayParam(_ key: String) -> [String]? {
        paramsObject?[key] as? [String]
    }

    public func intParam(_ key: String) -> Int? {
        paramsObject?[key] as? Int
    }

    public func boolParam(_ key: String) -> Bool? {
        paramsObject?[key] as? Bool
    }

    public var paramKeys: Set<String> {
        Set(paramsObject?.keys.map { $0 } ?? [])
    }

    public var subscriptions: [(type: String, paneId: String?)] {
        (paramsObject?["subscriptions"] as? [[String: Any]] ?? []).map { item in
            (item["type"] as? String ?? "", item["pane_id"] as? String)
        }
    }

    private var paramsObject: [String: Any]? {
        try? JSONSerialization.jsonObject(with: params) as? [String: Any]
    }
}

public enum FakeHerdrReply: Sendable {
    case result(Data)
    case error(code: String, message: String)
    case noReply
    case close
}

public actor FakeHerdrServer {
    public static let perPaneSubscriptionTypes: Set<String> = ["pane.agent_status_changed", "pane.scroll_changed", "pane.output_matched"]
    public static let validKeys: Set<String> = ["Escape", "esc", "enter", "Enter", "down", "up", "tab", "space"]

    private struct SubscriptionItem: Sendable {
        let type: String
        let paneId: String?
    }

    private struct StatusWaiter: Sendable {
        let requestId: String
        let target: String
        let until: Set<String>
    }

    public static let waitTimeoutMessage = "timed out waiting for agent status"

    public nonisolated let socketPath: String

    private let queue = DispatchQueue(label: "com.joaoalves.mocha.tests.fake-herdr")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var subscriptions: [UUID: [SubscriptionItem]] = [:]
    private var waiters: [UUID: StatusWaiter] = [:]
    private var schema: HerdrSchemaValidator?
    private var knownMethods: Set<String> = []
    private var knownSubscriptionTypes: Set<String> = []
    private var snapshot: [String: Any] = [:]
    private var version = "0.9.1"
    private var protocolVersion = 22
    private var overrides: [String: FakeHerdrReply] = [:]
    private var handlers: [String: @Sendable (FakeHerdrRequest) -> FakeHerdrReply] = [:]
    private var recordedRequests: [FakeHerdrRequest] = []
    private var acceptedConnections = 0
    private var writesAfterAckCount = 0

    public init(socketPath: String = FakeHerdrServer.temporarySocketPath()) {
        self.socketPath = socketPath
    }

    public static func temporarySocketPath() -> String {
        let name = "mh-\(UUID().uuidString.prefix(8).lowercased()).sock"
        let temporary = FileManager.default.temporaryDirectory.appending(path: name).path(percentEncoded: false)
        return temporary.utf8.count < 100 ? temporary : "/tmp/\(name)"
    }

    public func start() async throws {
        guard listener == nil else { return }
        if schema == nil {
            let schema = try HerdrSchemaValidator.load()
            knownMethods = schema.requestMethods
            knownSubscriptionTypes = schema.subscriptionTypes
            self.schema = schema
        }
        unlink(socketPath)
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .unix(path: socketPath)
        let listener = try NWListener(using: parameters)
        let (states, stateContinuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { state in
            stateContinuation.yield(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
        for await state in states {
            switch state {
            case .ready:
                listener.stateUpdateHandler = nil
                return
            case .failed(let error), .waiting(let error):
                listener.cancel()
                self.listener = nil
                throw error
            case .cancelled:
                self.listener = nil
                throw CancellationError()
            default:
                continue
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        subscriptions.removeAll()
        waiters.removeAll()
        unlink(socketPath)
    }

    public func loadSnapshot(fixture name: String) throws {
        let data = try HerdrFixtures.data(name)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = response["result"] as? [String: Any],
            let snapshot = result["snapshot"] as? [String: Any]
        else { throw CocoaError(.coderReadCorrupt) }
        self.snapshot = snapshot
    }

    public func setServerVersion(_ version: String, protocolVersion: Int) {
        self.version = version
        self.protocolVersion = protocolVersion
    }

    public func override(_ method: String, with reply: FakeHerdrReply?) {
        overrides[method] = reply
    }

    public func setHandler(_ method: String, _ handler: (@Sendable (FakeHerdrRequest) -> FakeHerdrReply)?) {
        handlers[method] = handler
    }

    public func setAgentSession(paneId: String, sessionId: String) {
        let session: [String: Any] = ["source": "herdr:claude", "agent": "claude", "kind": "id", "value": sessionId]
        mutateEntries(withPaneId: paneId) { $0["agent_session"] = session }
    }

    public func setAgentStatus(paneId: String, status: String) {
        mutateEntries(withPaneId: paneId) { $0["agent_status"] = status }
        resolveWaiters()
    }

    public func setTerminalTitle(paneId: String, title: String) {
        mutateEntries(withPaneId: paneId) { entry in
            entry["terminal_title"] = title
            entry["terminal_title_stripped"] = title
        }
    }

    public func setAgent(paneId: String, agent: String?) {
        var panes = entries("panes")
        guard let index = panes.firstIndex(where: { $0["pane_id"] as? String == paneId }) else { return }
        panes[index]["agent"] = agent
        if agent == nil {
            panes[index]["agent_status"] = "unknown"
            panes[index]["agent_session"] = nil
        }
        snapshot["panes"] = panes
        var agents = entries("agents").filter { $0["pane_id"] as? String != paneId }
        if agent != nil {
            agents.append(panes[index])
        }
        snapshot["agents"] = agents
        resolveWaiters()
    }

    public func removeTab(_ tabId: String) {
        snapshot["tabs"] = entries("tabs").filter { $0["tab_id"] as? String != tabId }
        snapshot["panes"] = entries("panes").filter { $0["tab_id"] as? String != tabId }
        snapshot["agents"] = entries("agents").filter { $0["tab_id"] as? String != tabId }
    }

    public func removePanes(_ paneIds: Set<String>) {
        snapshot["panes"] = entries("panes").filter { !paneIds.contains($0["pane_id"] as? String ?? "") }
        snapshot["agents"] = entries("agents").filter { !paneIds.contains($0["pane_id"] as? String ?? "") }
        dropEmptyTabs()
    }

    public func movePane(from oldPaneId: String, to newPaneId: String, tabId: String, workspaceId: String, tabLabel: String) {
        if !entries("tabs").contains(where: { $0["tab_id"] as? String == tabId }) {
            let number = (entries("tabs").compactMap { $0["number"] as? Int }.max() ?? 0) + 1
            let tab: [String: Any] = [
                "tab_id": tabId, "workspace_id": workspaceId, "number": number, "label": tabLabel,
                "focused": false, "pane_count": 1, "agent_status": "idle",
            ]
            snapshot["tabs"] = entries("tabs") + [tab]
        }
        mutateEntries(withPaneId: oldPaneId) { entry in
            entry["pane_id"] = newPaneId
            entry["tab_id"] = tabId
            entry["workspace_id"] = workspaceId
        }
        dropEmptyTabs()
    }

    public func emit(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let event = object["event"] as? String,
            let payload = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        else { return }
        let paneId = (object["data"] as? [String: Any])?["pane_id"] as? String
        var message = payload
        message.append(0x0A)
        for (id, items) in subscriptions where Self.matches(items, event: event, paneId: paneId) {
            connections[id]?.send(content: message, completion: .idempotent)
        }
    }

    public func emit(fixture name: String) throws {
        emit(try HerdrFixtures.data(name))
    }

    public func play(stream name: String) throws {
        for line in try HerdrFixtures.lines(name) {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["event"] != nil else { continue }
            emit(line)
        }
    }

    public var requests: [FakeHerdrRequest] {
        recordedRequests
    }

    public func requests(method: String) -> [FakeHerdrRequest] {
        recordedRequests.filter { $0.method == method }
    }

    public func clearRequests() {
        recordedRequests.removeAll()
    }

    public var connectionCount: Int {
        acceptedConnections
    }

    public var writesAfterAck: Int {
        writesAfterAckCount
    }

    public var isIdle: Bool {
        subscriptions.isEmpty
    }

    public var pendingWaitCount: Int {
        waiters.count
    }

    public var globalSubscriptionCount: Int {
        subscriptions.values.filter { items in items.contains { !Self.perPaneSubscriptionTypes.contains($0.type) } }.count
    }

    public var paneSubscriptionIds: [String] {
        subscriptions.values
            .flatMap { items in items.filter { Self.perPaneSubscriptionTypes.contains($0.type) }.compactMap(\.paneId) }
            .sorted()
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        let id = UUID()
        connections[id] = connection
        acceptedConnections += 1
        connection.start(queue: queue)
        Task { await self.serve(id, connection) }
    }

    private func serve(_ id: UUID, _ connection: NWConnection) async {
        var buffer = Data()
        while true {
            let chunk = await Self.receive(connection)
            buffer.append(chunk.bytes)
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                let rest = Data(buffer[buffer.index(after: newline)...])
                await process(line, rest: rest, id: id, connection: connection)
                return
            }
            if chunk.isEnd {
                close(id)
                return
            }
        }
    }

    private func process(_ line: Data, rest: Data, id: UUID, connection: NWConnection) async {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: malformed JSON"))
            return
        }
        guard let requestId = object["id"] as? String else {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: missing or non-string field `id`"))
            return
        }
        guard let method = object["method"] as? String else {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: missing field `method`"))
            return
        }
        guard let params = object["params"] as? [String: Any] else {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: missing field `params`"))
            return
        }
        guard knownMethods.contains(method) else {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: unknown variant `\(method)`"))
            return
        }
        if let violation = schema?.requestViolations(line, strict: false).first {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: \(violation)"))
            return
        }
        let paramsData = (try? JSONSerialization.data(withJSONObject: params)) ?? Data("{}".utf8)
        let request = FakeHerdrRequest(id: requestId, method: method, line: line, params: paramsData)
        recordedRequests.append(request)
        if method == "events.subscribe" {
            await subscribe(request, items: params["subscriptions"], rest: rest, id: id, connection: connection)
            return
        }
        if method == "agent.wait", handlers[method] == nil, overrides[method] == nil, let waiter = statusWaiter(for: request) {
            waiters[id] = waiter
            if let timeoutMs = request.intParam("timeout_ms") {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(timeoutMs))
                    await self?.expireWaiter(id)
                }
            }
            await waitForClose(id, connection: connection, countsWrites: false)
            return
        }
        let reply = reply(for: request)
        if case .noReply = reply {
            await waitForClose(id, connection: connection, countsWrites: false)
            return
        }
        respond(id, requestId: requestId, reply: reply)
    }

    private func subscribe(_ request: FakeHerdrRequest, items: Any?, rest: Data, id: UUID, connection: NWConnection) async {
        guard let list = items as? [[String: Any]] else {
            respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: missing field `subscriptions`"))
            return
        }
        var parsed: [SubscriptionItem] = []
        let knownPanes = Set(entries("panes").compactMap { $0["pane_id"] as? String })
        for (index, item) in list.enumerated() {
            guard let type = item["type"] as? String, knownSubscriptionTypes.contains(type) else {
                respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: unknown subscription type"))
                return
            }
            let paneId = item["pane_id"] as? String
            if Self.perPaneSubscriptionTypes.contains(type) {
                guard let paneId else {
                    respond(id, requestId: "", reply: .error(code: "invalid_request", message: "invalid request: missing field `pane_id`"))
                    return
                }
                guard knownPanes.contains(paneId) else {
                    respond(
                        id,
                        requestId: "\(request.id):sub:\(index):probe",
                        reply: .error(code: "pane_not_found", message: "pane \(paneId) not found")
                    )
                    return
                }
            }
            parsed.append(SubscriptionItem(type: type, paneId: paneId))
        }
        subscriptions[id] = parsed
        connection.send(content: Self.responseLine(requestId: request.id, body: "\"result\":{\"type\":\"subscription_started\"}"), completion: .idempotent)
        guard rest.isEmpty else {
            writesAfterAckCount += 1
            close(id)
            return
        }
        await waitForClose(id, connection: connection, countsWrites: true)
    }

    private func waitForClose(_ id: UUID, connection: NWConnection, countsWrites: Bool) async {
        while connections[id] != nil {
            let chunk = await Self.receive(connection)
            if !chunk.bytes.isEmpty, countsWrites {
                writesAfterAckCount += 1
                close(id)
                return
            }
            if chunk.isEnd {
                close(id)
                return
            }
        }
    }

    private func statusWaiter(for request: FakeHerdrRequest) -> StatusWaiter? {
        guard let target = request.stringParam("target"), let agent = agent(target) else { return nil }
        let until = Set(request.stringArrayParam("until") ?? [])
        guard let status = agent["agent_status"] as? String, !until.contains(status) else { return nil }
        return StatusWaiter(requestId: request.id, target: target, until: until)
    }

    private func resolveWaiters() {
        for (id, waiter) in waiters {
            guard let agent = agent(waiter.target), let status = agent["agent_status"] as? String, waiter.until.contains(status) else {
                continue
            }
            waiters[id] = nil
            respond(id, requestId: waiter.requestId, reply: result(["type": "agent_info", "agent": agent]))
        }
    }

    private func expireWaiter(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        respond(id, requestId: waiter.requestId, reply: .error(code: "timeout", message: Self.waitTimeoutMessage))
    }

    private func respond(_ id: UUID, requestId: String, reply: FakeHerdrReply) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        subscriptions[id] = nil
        waiters[id] = nil
        let body: String
        switch reply {
        case .result(let result):
            body = "\"result\":" + String(decoding: result, as: UTF8.self)
        case .error(let code, let message):
            let error = (try? JSONSerialization.data(withJSONObject: ["code": code, "message": message], options: [.sortedKeys])) ?? Data()
            body = "\"error\":" + String(decoding: error, as: UTF8.self)
        case .noReply, .close:
            connection.cancel()
            return
        }
        let responseId = if case .error("invalid_request", _) = reply { "" } else { requestId }
        connection.send(
            content: Self.responseLine(requestId: responseId, body: body),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        subscriptions[id] = nil
        waiters[id] = nil
    }

    private func reply(for request: FakeHerdrRequest) -> FakeHerdrReply {
        if let handler = handlers[request.method] {
            return handler(request)
        }
        if let reply = overrides[request.method] {
            return reply
        }
        switch request.method {
        case "ping":
            return result([
                "type": "pong", "version": version, "protocol": protocolVersion,
                "capabilities": ["live_handoff": true, "health_check": true],
            ])
        case "session.snapshot":
            var current = snapshot
            current["version"] = version
            current["protocol"] = protocolVersion
            return result(["type": "session_snapshot", "snapshot": current])
        case "agent.list":
            return result(["type": "agent_list", "agents": entries("agents")])
        case "agent.get":
            guard let agent = agent(request.stringParam("target")) else { return agentNotFound(request) }
            return result(["type": "agent_info", "agent": agent])
        case "agent.prompt":
            guard let agent = agent(request.stringParam("target")) else { return agentNotFound(request) }
            guard agent["agent_status"] as? String != "blocked" else {
                return .error(code: "agent_blocked", message: "agent \(agent["pane_id"] as? String ?? "") is blocked and requires interactive input")
            }
            return result(["type": "agent_prompted", "agent": agent])
        case "agent.send_keys":
            guard agent(request.stringParam("target")) != nil else { return agentNotFound(request) }
            if let invalid = request.stringArrayParam("keys")?.first(where: { !Self.validKeys.contains($0) }) {
                return .error(code: "invalid_key", message: "unsupported key \(invalid)")
            }
            return result(["type": "ok"])
        case "workspace.list":
            return result(["type": "workspace_list", "workspaces": entries("workspaces")])
        case "tab.list":
            let workspaceId = request.stringParam("workspace_id")
            let tabs = entries("tabs").filter { workspaceId == nil || $0["workspace_id"] as? String == workspaceId }
            return result(["type": "tab_list", "tabs": tabs])
        case "pane.get":
            let paneId = request.stringParam("pane_id") ?? ""
            guard let pane = entries("panes").first(where: { $0["pane_id"] as? String == paneId }) else {
                return .error(code: "pane_not_found", message: "pane \(paneId) not found")
            }
            return result(["type": "pane_info", "pane": pane])
        case "tab.create":
            return createTab(request)
        case "agent.start":
            return startAgent(request)
        case "agent.wait":
            guard let agent = agent(request.stringParam("target")) else { return agentNotFound(request) }
            return result(["type": "agent_info", "agent": agent])
        default:
            return .error(code: "fake_unconfigured", message: "fake Herdr has no reply for \(request.method)")
        }
    }

    private func createTab(_ request: FakeHerdrRequest) -> FakeHerdrReply {
        let workspaceId = request.stringParam("workspace_id") ?? ""
        guard entries("workspaces").contains(where: { $0["workspace_id"] as? String == workspaceId }) else {
            return .error(code: "not_found", message: "workspace \(workspaceId) not found")
        }
        let tabIds = Set(entries("tabs").compactMap { $0["tab_id"] as? String })
        let paneIds = Set(entries("panes").compactMap { $0["pane_id"] as? String })
        let number = (entries("tabs").filter { $0["workspace_id"] as? String == workspaceId }.compactMap { $0["number"] as? Int }.max() ?? 0) + 1
        var tabSuffix = number
        while tabIds.contains("\(workspaceId):t\(tabSuffix)") {
            tabSuffix += 1
        }
        var paneSuffix = 1
        while paneIds.contains("\(workspaceId):p\(paneSuffix)") {
            paneSuffix += 1
        }
        let tabId = "\(workspaceId):t\(tabSuffix)"
        let paneId = "\(workspaceId):p\(paneSuffix)"
        let cwd = request.stringParam("cwd") ?? "/Users/dev"
        let tab: [String: Any] = [
            "tab_id": tabId, "workspace_id": workspaceId, "number": number, "label": request.stringParam("label") ?? "\(number)",
            "focused": false, "pane_count": 1, "agent_status": "unknown",
        ]
        let pane: [String: Any] = [
            "pane_id": paneId, "terminal_id": "term_\(workspaceId)_\(paneSuffix)", "workspace_id": workspaceId, "tab_id": tabId,
            "focused": false, "cwd": cwd, "foreground_cwd": cwd, "agent_status": "unknown",
            "scroll": ["offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": 41], "revision": 0,
        ]
        snapshot["tabs"] = entries("tabs") + [tab]
        snapshot["panes"] = entries("panes") + [pane]
        return result(["type": "tab_created", "tab": tab, "root_pane": pane])
    }

    private func startAgent(_ request: FakeHerdrRequest) -> FakeHerdrReply {
        let paneId = request.stringParam("pane_id") ?? ""
        let name = request.stringParam("name") ?? ""
        guard var pane = entries("panes").first(where: { $0["pane_id"] as? String == paneId }) else {
            return .error(code: "pane_not_found", message: "pane \(paneId) not found")
        }
        guard !entries("agents").contains(where: { $0["name"] as? String == name }) else {
            return .error(code: "invalid_params", message: "agent name \(name) is already in use")
        }
        pane["name"] = name
        pane["launch_pending"] = true
        pane["state_change_seq"] = 0
        pane["scroll"] = nil
        mutateEntries(withPaneId: paneId) { entry in
            entry["name"] = name
        }
        snapshot["agents"] = entries("agents").filter { $0["pane_id"] as? String != paneId } + [pane]
        return result(["type": "agent_started", "agent": pane, "argv": ["claude"] + (request.stringArrayParam("args") ?? [])])
    }

    private func agent(_ target: String?) -> [String: Any]? {
        guard let target else { return nil }
        return entries("agents").first { $0["pane_id"] as? String == target || $0["name"] as? String == target }
    }

    private func agentNotFound(_ request: FakeHerdrRequest) -> FakeHerdrReply {
        .error(code: "agent_not_found", message: "agent target \(request.stringParam("target") ?? "") not found")
    }

    private func result(_ object: [String: Any]) -> FakeHerdrReply {
        .result((try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8))
    }

    private func entries(_ key: String) -> [[String: Any]] {
        snapshot[key] as? [[String: Any]] ?? []
    }

    private func mutateEntries(withPaneId paneId: String, _ mutate: (inout [String: Any]) -> Void) {
        for key in ["panes", "agents"] {
            var list = entries(key)
            for index in list.indices where list[index]["pane_id"] as? String == paneId {
                mutate(&list[index])
            }
            snapshot[key] = list
        }
    }

    private func dropEmptyTabs() {
        let tabsWithPanes = Set(entries("panes").compactMap { $0["tab_id"] as? String })
        snapshot["tabs"] = entries("tabs").filter { tabsWithPanes.contains($0["tab_id"] as? String ?? "") }
    }

    private static func matches(_ items: [SubscriptionItem], event: String, paneId: String?) -> Bool {
        items.contains { item in
            if perPaneSubscriptionTypes.contains(item.type) {
                return item.type == event && item.paneId == paneId
            }
            return item.type.replacingOccurrences(of: ".", with: "_") == event
        }
    }

    private static func responseLine(requestId: String, body: String) -> Data {
        let encodedId = (try? JSONSerialization.data(withJSONObject: requestId, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
        return Data(("{\"id\":" + String(decoding: encodedId, as: UTF8.self) + "," + body + "}\n").utf8)
    }

    private static func receive(_ connection: NWConnection) async -> (bytes: Data, isEnd: Bool) {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { content, _, isComplete, error in
                continuation.resume(returning: (content ?? Data(), isComplete || error != nil))
            }
        }
    }
}
