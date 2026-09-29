import Foundation

public enum HerdrAgentStatus: String, Sendable, Hashable, Decodable {
    case idle
    case working
    case blocked
    case done
    case unknown

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = HerdrAgentStatus(rawValue: rawValue) ?? .unknown
    }
}

public struct HerdrWorktree: Sendable, Hashable, Decodable {
    public var repoKey: String
    public var repoName: String
    public var repoRoot: String
    public var checkoutPath: String
    public var isLinkedWorktree: Bool

    public init(repoKey: String, repoName: String, repoRoot: String, checkoutPath: String, isLinkedWorktree: Bool) {
        self.repoKey = repoKey
        self.repoName = repoName
        self.repoRoot = repoRoot
        self.checkoutPath = checkoutPath
        self.isLinkedWorktree = isLinkedWorktree
    }

    private enum CodingKeys: String, CodingKey {
        case repoKey = "repo_key"
        case repoName = "repo_name"
        case repoRoot = "repo_root"
        case checkoutPath = "checkout_path"
        case isLinkedWorktree = "is_linked_worktree"
    }
}

public struct HerdrWorkspace: Sendable, Hashable, Decodable {
    public var workspaceId: String
    public var number: Int
    public var label: String
    public var activeTabId: String?
    public var agentStatus: HerdrAgentStatus
    public var worktree: HerdrWorktree?

    public init(
        workspaceId: String,
        number: Int,
        label: String,
        activeTabId: String? = nil,
        agentStatus: HerdrAgentStatus = .unknown,
        worktree: HerdrWorktree? = nil
    ) {
        self.workspaceId = workspaceId
        self.number = number
        self.label = label
        self.activeTabId = activeTabId
        self.agentStatus = agentStatus
        self.worktree = worktree
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case number
        case label
        case activeTabId = "active_tab_id"
        case agentStatus = "agent_status"
        case worktree
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        number = try container.decode(Int.self, forKey: .number)
        label = try container.decode(String.self, forKey: .label)
        activeTabId = try container.decodeIfPresent(String.self, forKey: .activeTabId)
        agentStatus = try container.decodeIfPresent(HerdrAgentStatus.self, forKey: .agentStatus) ?? .unknown
        worktree = try container.decodeIfPresent(HerdrWorktree.self, forKey: .worktree)
    }
}

public struct HerdrTab: Sendable, Hashable, Decodable {
    public var tabId: String
    public var workspaceId: String
    public var number: Int
    public var label: String

    public init(tabId: String, workspaceId: String, number: Int, label: String) {
        self.tabId = tabId
        self.workspaceId = workspaceId
        self.number = number
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case workspaceId = "workspace_id"
        case number
        case label
    }
}

public struct HerdrAgentSession: Sendable, Hashable, Decodable {
    public var value: String

    public init(value: String) {
        self.value = value
    }
}

public struct HerdrPane: Sendable, Hashable, Decodable {
    public var paneId: String
    public var workspaceId: String
    public var tabId: String
    public var agent: String?
    public var agentStatus: HerdrAgentStatus
    public var agentSession: HerdrAgentSession?
    public var cwd: String?
    public var foregroundCwd: String?
    public var terminalTitleStripped: String?
    public var name: String?

    public init(
        paneId: String,
        workspaceId: String,
        tabId: String,
        agent: String? = nil,
        agentStatus: HerdrAgentStatus = .unknown,
        agentSession: HerdrAgentSession? = nil,
        cwd: String? = nil,
        foregroundCwd: String? = nil,
        terminalTitleStripped: String? = nil,
        name: String? = nil
    ) {
        self.paneId = paneId
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.agent = agent
        self.agentStatus = agentStatus
        self.agentSession = agentSession
        self.cwd = cwd
        self.foregroundCwd = foregroundCwd
        self.terminalTitleStripped = terminalTitleStripped
        self.name = name
    }

    public var sessionId: String? {
        agentSession?.value
    }

    private enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case workspaceId = "workspace_id"
        case tabId = "tab_id"
        case agent
        case agentStatus = "agent_status"
        case agentSession = "agent_session"
        case cwd
        case foregroundCwd = "foreground_cwd"
        case terminalTitleStripped = "terminal_title_stripped"
        case name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paneId = try container.decode(String.self, forKey: .paneId)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        tabId = try container.decode(String.self, forKey: .tabId)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        agentStatus = try container.decodeIfPresent(HerdrAgentStatus.self, forKey: .agentStatus) ?? .unknown
        agentSession = try container.decodeIfPresent(HerdrAgentSession.self, forKey: .agentSession)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        foregroundCwd = try container.decodeIfPresent(String.self, forKey: .foregroundCwd)
        terminalTitleStripped = try container.decodeIfPresent(String.self, forKey: .terminalTitleStripped)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

public struct HerdrSessionSnapshot: Sendable, Hashable, Decodable {
    public var version: String
    public var protocolVersion: Int
    public var workspaces: [HerdrWorkspace]
    public var tabs: [HerdrTab]
    public var panes: [HerdrPane]
    public var agents: [HerdrPane]

    public init(
        version: String,
        protocolVersion: Int,
        workspaces: [HerdrWorkspace],
        tabs: [HerdrTab],
        panes: [HerdrPane],
        agents: [HerdrPane]
    ) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.workspaces = workspaces
        self.tabs = tabs
        self.panes = panes
        self.agents = agents
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case protocolVersion = "protocol"
        case workspaces
        case tabs
        case panes
        case agents
    }
}

public struct HerdrPong: Sendable, Hashable, Decodable {
    public var version: String
    public var protocolVersion: Int

    public init(version: String, protocolVersion: Int) {
        self.version = version
        self.protocolVersion = protocolVersion
    }

    public var isSupportedProtocol: Bool {
        protocolVersion == HerdrProtocol.supportedVersion
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case protocolVersion = "protocol"
    }
}

public struct HerdrTabCreated: Sendable, Hashable, Decodable {
    public var tab: HerdrTab
    public var rootPane: HerdrPane

    public init(tab: HerdrTab, rootPane: HerdrPane) {
        self.tab = tab
        self.rootPane = rootPane
    }

    private enum CodingKeys: String, CodingKey {
        case tab
        case rootPane = "root_pane"
    }
}

public struct HerdrAgentStarted: Sendable, Hashable, Decodable {
    public var agent: HerdrPane
    public var argv: [String]

    public init(agent: HerdrPane, argv: [String]) {
        self.agent = agent
        self.argv = argv
    }
}

public enum HerdrReadSource: String, Sendable, Hashable, Decodable {
    case visible
    case recent
    case recentUnwrapped = "recent_unwrapped"
    case detection
}

public struct HerdrPaneRead: Sendable, Hashable, Decodable {
    public var paneId: String
    public var workspaceId: String
    public var tabId: String
    public var text: String
    public var revision: UInt64
    public var truncated: Bool

    public init(paneId: String, workspaceId: String, tabId: String, text: String, revision: UInt64 = 0, truncated: Bool = false) {
        self.paneId = paneId
        self.workspaceId = workspaceId
        self.tabId = tabId
        self.text = text
        self.revision = revision
        self.truncated = truncated
    }

    private enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case workspaceId = "workspace_id"
        case tabId = "tab_id"
        case text
        case revision
        case truncated
    }
}
