import Foundation

public enum HerdrGlobalEventType: String, Sendable, Hashable, CaseIterable {
    case workspaceCreated = "workspace.created"
    case workspaceUpdated = "workspace.updated"
    case workspaceRenamed = "workspace.renamed"
    case workspaceMoved = "workspace.moved"
    case workspaceReordered = "workspace.reordered"
    case workspaceClosed = "workspace.closed"
    case worktreeCreated = "worktree.created"
    case worktreeOpened = "worktree.opened"
    case worktreeRemoved = "worktree.removed"
    case tabCreated = "tab.created"
    case tabClosed = "tab.closed"
    case tabRenamed = "tab.renamed"
    case tabMoved = "tab.moved"
    case paneCreated = "pane.created"
    case paneClosed = "pane.closed"
    case paneUpdated = "pane.updated"
    case paneMoved = "pane.moved"
    case paneExited = "pane.exited"
    case paneAgentDetected = "pane.agent_detected"

    public var wireEventName: String {
        rawValue.replacingOccurrences(of: ".", with: "_")
    }
}

public enum HerdrSubscription: Sendable, Hashable, Encodable {
    case global(HerdrGlobalEventType)
    case agentStatusChanged(paneId: String)

    public static let agentStatusChangedType = "pane.agent_status_changed"

    public static let globalLifecycle: [HerdrSubscription] = HerdrGlobalEventType.allCases.map { .global($0) }

    private enum CodingKeys: String, CodingKey {
        case type
        case paneId = "pane_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global(let type):
            try container.encode(type.rawValue, forKey: .type)
        case .agentStatusChanged(let paneId):
            try container.encode(Self.agentStatusChangedType, forKey: .type)
            try container.encode(paneId, forKey: .paneId)
        }
    }
}

public enum HerdrRequest: Sendable, Hashable {
    case ping
    case sessionSnapshot
    case agentList
    case agentGet(target: String)
    case workspaceList
    case tabList(workspaceId: String?)
    case paneGet(paneId: String)
    case paneRead(paneId: String, source: HerdrReadSource, lines: Int?)
    case paneClose(paneId: String)
    case agentPrompt(target: String, text: String)
    case agentSendKeys(target: String, keys: [String])
    case tabCreate(workspaceId: String, cwd: String?)
    case agentStart(name: String, kind: String, paneId: String, args: [String], timeoutMs: Int?)
    case agentWait(target: String, until: [HerdrAgentStatus], timeoutMs: Int)
    case eventsSubscribe([HerdrSubscription])

    public var method: String {
        switch self {
        case .ping: "ping"
        case .sessionSnapshot: "session.snapshot"
        case .agentList: "agent.list"
        case .agentGet: "agent.get"
        case .workspaceList: "workspace.list"
        case .tabList: "tab.list"
        case .paneGet: "pane.get"
        case .paneRead: "pane.read"
        case .paneClose: "pane.close"
        case .agentPrompt: "agent.prompt"
        case .agentSendKeys: "agent.send_keys"
        case .tabCreate: "tab.create"
        case .agentStart: "agent.start"
        case .agentWait: "agent.wait"
        case .eventsSubscribe: "events.subscribe"
        }
    }

    public func encodedLine(id: String) throws -> Data {
        var line = try JSONEncoder.herdrRequest.encode(Envelope(id: id, method: method, params: Params(request: self)))
        line.append(0x0A)
        return line
    }

    private struct Envelope: Encodable {
        let id: String
        let method: String
        let params: Params
    }

    private struct Params: Encodable {
        let request: HerdrRequest

        private enum CodingKeys: String, CodingKey {
            case target
            case text
            case keys
            case workspaceId = "workspace_id"
            case paneId = "pane_id"
            case subscriptions
            case cwd
            case focus
            case name
            case kind
            case args
            case until
            case timeoutMs = "timeout_ms"
            case source
            case lines
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch request {
            case .ping, .sessionSnapshot, .agentList, .workspaceList:
                break
            case .agentGet(let target):
                try container.encode(target, forKey: .target)
            case .tabList(let workspaceId):
                try container.encodeIfPresent(workspaceId, forKey: .workspaceId)
            case .paneGet(let paneId), .paneClose(let paneId):
                try container.encode(paneId, forKey: .paneId)
            case .paneRead(let paneId, let source, let lines):
                try container.encode(paneId, forKey: .paneId)
                try container.encode(source.rawValue, forKey: .source)
                try container.encodeIfPresent(lines, forKey: .lines)
            case .agentPrompt(let target, let text):
                try container.encode(target, forKey: .target)
                try container.encode(text, forKey: .text)
            case .agentSendKeys(let target, let keys):
                try container.encode(target, forKey: .target)
                try container.encode(keys, forKey: .keys)
            case .tabCreate(let workspaceId, let cwd):
                try container.encode(workspaceId, forKey: .workspaceId)
                try container.encodeIfPresent(cwd, forKey: .cwd)
                try container.encode(false, forKey: .focus)
            case .agentStart(let name, let kind, let paneId, let args, let timeoutMs):
                try container.encode(name, forKey: .name)
                try container.encode(kind, forKey: .kind)
                try container.encode(paneId, forKey: .paneId)
                try container.encode(args, forKey: .args)
                try container.encodeIfPresent(timeoutMs, forKey: .timeoutMs)
            case .agentWait(let target, let until, let timeoutMs):
                try container.encode(target, forKey: .target)
                try container.encode(until.map(\.rawValue), forKey: .until)
                try container.encode(timeoutMs, forKey: .timeoutMs)
            case .eventsSubscribe(let subscriptions):
                try container.encode(subscriptions, forKey: .subscriptions)
            }
        }
    }
}

extension JSONEncoder {
    fileprivate static var herdrRequest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
