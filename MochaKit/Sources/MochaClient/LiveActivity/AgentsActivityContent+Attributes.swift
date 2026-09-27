#if os(iOS)
import MochaProtocol

extension AgentsActivityContent {
    public init(_ state: MochaAgentAttributes.ContentState) {
        self.init(
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

    public var attributesState: MochaAgentAttributes.ContentState {
        MochaAgentAttributes.ContentState(
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
                MochaAgentAttributes.ContentState.Pending(
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
    init(_ kind: MochaAgentAttributes.ContentState.Pending.Kind) {
        switch kind {
        case .permission: self = .permission
        case .question: self = .question
        }
    }

    var attributesKind: MochaAgentAttributes.ContentState.Pending.Kind {
        switch self {
        case .permission: .permission
        case .question: .question
        }
    }
}
#endif
