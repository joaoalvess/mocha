#if os(iOS)
import MochaProtocol

extension AgentsActivityContent {
    public init(_ state: MochaAgentsAttributes.ContentState) {
        self.init(
            working: state.working,
            waiting: state.waiting,
            highlight: state.highlight.map {
                Highlight(
                    agentId: $0.agentId,
                    title: $0.title,
                    workspaceLabel: $0.workspaceLabel,
                    status: $0.status,
                    since: $0.since,
                    tabTitle: $0.tabTitle,
                    model: $0.model,
                    contextLeftPercent: $0.contextLeftPercent,
                    preview: $0.preview,
                    activity: $0.activity
                )
            },
            pending: state.pending.map {
                Pending(requestId: $0.requestId, agentId: $0.agentId, kind: Pending.Kind($0.kind), toolName: $0.toolName, text: $0.text, options: $0.options)
            },
            updatedAt: state.updatedAt
        )
    }

    public var attributesState: MochaAgentsAttributes.ContentState {
        MochaAgentsAttributes.ContentState(
            working: working,
            waiting: waiting,
            highlight: highlight.map {
                MochaAgentsAttributes.ContentState.Highlight(
                    agentId: $0.agentId,
                    title: $0.title,
                    workspaceLabel: $0.workspaceLabel,
                    status: $0.status,
                    since: $0.since,
                    tabTitle: $0.tabTitle,
                    model: $0.model,
                    contextLeftPercent: $0.contextLeftPercent,
                    preview: $0.preview,
                    activity: $0.activity
                )
            },
            pending: pending.map {
                MochaAgentsAttributes.ContentState.Pending(
                    requestId: $0.requestId,
                    agentId: $0.agentId,
                    kind: $0.kind.attributesKind,
                    toolName: $0.toolName,
                    text: $0.text,
                    options: $0.options
                )
            },
            updatedAt: updatedAt
        )
    }
}

extension AgentsActivityContent.Pending.Kind {
    init(_ kind: MochaAgentsAttributes.ContentState.Pending.Kind) {
        switch kind {
        case .permission: self = .permission
        case .question: self = .question
        }
    }

    var attributesKind: MochaAgentsAttributes.ContentState.Pending.Kind {
        switch self {
        case .permission: .permission
        case .question: .question
        }
    }
}
#endif
