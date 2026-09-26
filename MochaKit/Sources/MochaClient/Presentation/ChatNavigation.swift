import MochaProtocol

public enum ChatNavigationStep: Sendable, Equatable {
    case stay
    case show(path: [ChatTarget], closing: ChatTarget?)
}

public enum ChatNavigation {
    public static func open(_ target: ChatTarget, visibleRoute: ChatTarget?, visibleTarget: ChatTarget?) -> ChatNavigationStep {
        if visibleRoute == target || visibleTarget == target {
            return .stay
        }
        return .show(path: [target], closing: visibleTarget)
    }
}
