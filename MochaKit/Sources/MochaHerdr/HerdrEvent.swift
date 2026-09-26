import Foundation

public enum HerdrEvent: Sendable, Hashable {
    case workspaceRenamed(workspaceId: String, label: String)
    case tabRenamed(tabId: String, workspaceId: String, label: String)
    case paneUpdated(HerdrPane)
    case paneClosed(paneId: String, workspaceId: String)
    case paneExited(paneId: String, workspaceId: String)
    case paneMoved(previousPaneId: String, pane: HerdrPane)
    case paneAgentDetected(paneId: String, workspaceId: String, agent: String?, released: Bool)
    case agentStatusChanged(paneId: String, workspaceId: String, status: HerdrAgentStatus, agent: String?)
    case structural(String)
    case ignored(String)

    public static let structuralEventNames: Set<String> = [
        "workspace_created",
        "workspace_updated",
        "workspace_moved",
        "workspace_reordered",
        "workspace_closed",
        "worktree_created",
        "worktree_opened",
        "worktree_removed",
        "tab_created",
        "tab_closed",
        "tab_moved",
        "pane_created",
    ]

    public var requiresSnapshot: Bool {
        switch self {
        case .structural, .paneClosed, .paneExited, .paneMoved, .paneAgentDetected:
            true
        case .workspaceRenamed, .tabRenamed, .paneUpdated, .agentStatusChanged, .ignored:
            false
        }
    }

    public init?(line: Data) {
        let decoder = JSONDecoder()
        guard let head = try? decoder.decode(Head.self, from: line), let name = head.event else { return nil }
        self = Self.decode(name: name, line: line, decoder: decoder) ?? .ignored(name)
    }

    private static func decode(name: String, line: Data, decoder: JSONDecoder) -> HerdrEvent? {
        switch name {
        case "workspace_renamed":
            guard let data = try? decoder.decode(Envelope<Renamed>.self, from: line).data, let workspaceId = data.workspaceId else { return nil }
            return .workspaceRenamed(workspaceId: workspaceId, label: data.label)
        case "tab_renamed":
            guard let data = try? decoder.decode(Envelope<Renamed>.self, from: line).data,
                let tabId = data.tabId,
                let workspaceId = data.workspaceId
            else { return nil }
            return .tabRenamed(tabId: tabId, workspaceId: workspaceId, label: data.label)
        case "pane_updated":
            guard let data = try? decoder.decode(Envelope<PaneCarrier>.self, from: line).data else { return nil }
            return .paneUpdated(data.pane)
        case "pane_closed":
            guard let data = try? decoder.decode(Envelope<PaneReference>.self, from: line).data else { return nil }
            return .paneClosed(paneId: data.paneId, workspaceId: data.workspaceId)
        case "pane_exited":
            guard let data = try? decoder.decode(Envelope<PaneReference>.self, from: line).data else { return nil }
            return .paneExited(paneId: data.paneId, workspaceId: data.workspaceId)
        case "pane_moved":
            guard let data = try? decoder.decode(Envelope<PaneMoved>.self, from: line).data else { return nil }
            return .paneMoved(previousPaneId: data.previousPaneId, pane: data.pane)
        case "pane_agent_detected":
            guard let data = try? decoder.decode(Envelope<AgentDetected>.self, from: line).data else { return nil }
            return .paneAgentDetected(
                paneId: data.paneId,
                workspaceId: data.workspaceId,
                agent: data.agent,
                released: data.released ?? false
            )
        case HerdrSubscription.agentStatusChangedType:
            guard let data = try? decoder.decode(Envelope<StatusChanged>.self, from: line).data else { return nil }
            return .agentStatusChanged(paneId: data.paneId, workspaceId: data.workspaceId, status: data.agentStatus, agent: data.agent)
        default:
            return structuralEventNames.contains(name) ? .structural(name) : .ignored(name)
        }
    }

    private struct Head: Decodable {
        let event: String?
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload
    }

    private struct Renamed: Decodable {
        let workspaceId: String?
        let tabId: String?
        let label: String

        private enum CodingKeys: String, CodingKey {
            case workspaceId = "workspace_id"
            case tabId = "tab_id"
            case label
        }
    }

    private struct PaneCarrier: Decodable {
        let pane: HerdrPane
    }

    private struct PaneReference: Decodable {
        let paneId: String
        let workspaceId: String

        private enum CodingKeys: String, CodingKey {
            case paneId = "pane_id"
            case workspaceId = "workspace_id"
        }
    }

    private struct PaneMoved: Decodable {
        let previousPaneId: String
        let pane: HerdrPane

        private enum CodingKeys: String, CodingKey {
            case previousPaneId = "previous_pane_id"
            case pane
        }
    }

    private struct AgentDetected: Decodable {
        let paneId: String
        let workspaceId: String
        let agent: String?
        let released: Bool?

        private enum CodingKeys: String, CodingKey {
            case paneId = "pane_id"
            case workspaceId = "workspace_id"
            case agent
            case released
        }
    }

    private struct StatusChanged: Decodable {
        let paneId: String
        let workspaceId: String
        let agentStatus: HerdrAgentStatus
        let agent: String?

        private enum CodingKeys: String, CodingKey {
            case paneId = "pane_id"
            case workspaceId = "workspace_id"
            case agentStatus = "agent_status"
            case agent
        }
    }
}
