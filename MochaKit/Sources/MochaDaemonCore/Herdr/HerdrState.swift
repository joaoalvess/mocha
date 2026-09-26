import MochaHerdr

struct HerdrState: Sendable, Equatable {
    var workspaces: [HerdrWorkspace] = []
    var tabs: [HerdrTab] = []
    var panes: [HerdrPane] = []

    init() {}

    init(snapshot: HerdrSessionSnapshot) {
        workspaces = snapshot.workspaces
        tabs = snapshot.tabs
        panes = snapshot.panes
        for agent in snapshot.agents where !panes.contains(where: { $0.paneId == agent.paneId }) {
            panes.append(agent)
        }
    }

    func pane(_ id: String) -> HerdrPane? {
        panes.first { $0.paneId == id }
    }

    func workspace(_ id: String) -> HerdrWorkspace? {
        workspaces.first { $0.workspaceId == id }
    }

    var agentPaneIds: [String] {
        panes.filter { $0.agent != nil }.map(\.paneId)
    }

    mutating func updatePane(_ id: String, _ update: (inout HerdrPane) -> Void) {
        guard let index = panes.firstIndex(where: { $0.paneId == id }) else { return }
        update(&panes[index])
    }

    mutating func replacePane(_ oldId: String, with pane: HerdrPane) {
        panes.removeAll { $0.paneId == oldId || $0.paneId == pane.paneId }
        panes.append(pane)
    }

    mutating func renameWorkspace(_ id: String, label: String) -> Bool {
        guard let index = workspaces.firstIndex(where: { $0.workspaceId == id }), workspaces[index].label != label else { return false }
        workspaces[index].label = label
        return true
    }

    mutating func renameTab(_ id: String, label: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.tabId == id }), tabs[index].label != label else { return false }
        tabs[index].label = label
        return true
    }
}
