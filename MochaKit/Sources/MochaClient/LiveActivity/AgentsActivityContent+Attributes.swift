#if os(iOS)
import MochaProtocol

extension AgentsActivityContent {
    public init(_ state: MochaFeedAttributes.ContentState) {
        self.init(
            agentId: state.agentId,
            status: state.status,
            title: state.title,
            workspaceLabel: state.workspaceLabel,
            since: state.since,
            model: state.model,
            contextLeftPercent: state.contextLeftPercent,
            preview: state.preview,
            activity: state.activity,
            prompt: state.prompt,
            pending: state.pending.map {
                Pending(requestId: $0.requestId, kind: Pending.Kind($0.kind), toolName: $0.toolName, text: $0.text, options: $0.options)
            },
            updatedAt: state.updatedAt
        )
    }

    public var attributesState: MochaFeedAttributes.ContentState {
        MochaFeedAttributes.ContentState(
            agentId: agentId,
            status: status,
            title: title,
            workspaceLabel: workspaceLabel,
            since: since,
            model: model,
            contextLeftPercent: contextLeftPercent,
            preview: preview,
            activity: activity,
            prompt: prompt,
            pending: pending.map {
                MochaFeedAttributes.ContentState.Pending(
                    requestId: $0.requestId,
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
    init(_ kind: MochaFeedAttributes.ContentState.Pending.Kind) {
        switch kind {
        case .permission: self = .permission
        case .question: self = .question
        }
    }

    var attributesKind: MochaFeedAttributes.ContentState.Pending.Kind {
        switch self {
        case .permission: .permission
        case .question: .question
        }
    }
}
#endif
