import MochaProtocol

public enum PlanApproval {
    public static let buttonTitle = "Implementar plano"
    public static let prompt = "Implemente o plano."

    public static func planItemId(
        provider: AgentProvider,
        permissionMode: String?,
        status: AgentStatus,
        canSend: Bool,
        items: [ChatItem]
    ) -> String? {
        guard
            provider == .codex,
            canSend,
            permissionMode == PermissionModeTarget.plan.rawValue,
            status == .idle || status == .done,
            let last = items.last(where: { !isTurnFooter($0) }),
            case .plan = last.kind
        else { return nil }
        return last.id
    }

    private static func isTurnFooter(_ item: ChatItem) -> Bool {
        if case .turnFooter = item.kind { true } else { false }
    }
}
