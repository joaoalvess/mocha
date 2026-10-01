import MochaProtocol

public struct ChatStackEntry: Sendable, Equatable {
    public let route: ChatTarget
    public let target: ChatTarget

    public init(route: ChatTarget, target: ChatTarget) {
        self.route = route
        self.target = target
    }

    func matches(_ other: ChatTarget) -> Bool {
        route == other || target == other
    }
}

public enum ChatNavigationStep: Sendable, Equatable {
    case stay
    case show(path: [ChatTarget], closing: [ChatTarget])
}

public enum ChatNavigation {
    public static func open(_ target: ChatTarget, stack: [ChatStackEntry]) -> ChatNavigationStep {
        if case .subagent = target {
            return openSubagent(target, stack: stack)
        }
        if stack.last?.matches(target) == true {
            return .stay
        }
        if let index = stack.firstIndex(where: { $0.matches(target) }) {
            return popping(to: index + 1, in: stack)
        }
        return .show(path: [target], closing: stack.map(\.target))
    }

    public static func openSubagent(_ target: ChatTarget, stack: [ChatStackEntry]) -> ChatNavigationStep {
        if stack.last?.matches(target) == true {
            return .stay
        }
        if let index = stack.firstIndex(where: { $0.matches(target) }) {
            return popping(to: index + 1, in: stack)
        }
        return .show(path: stack.map(\.route) + [target], closing: [])
    }

    public static func setPath(_ path: [ChatTarget], stack: [ChatStackEntry]) -> ChatNavigationStep {
        let routes = stack.map(\.route)
        if path == routes {
            return .stay
        }
        if path.count < routes.count, Array(routes.prefix(path.count)) == path {
            return popping(to: path.count, in: stack)
        }
        guard let target = path.last else { return .stay }
        return open(target, stack: stack)
    }

    public static func back(stack: [ChatStackEntry]) -> ChatNavigationStep {
        guard !stack.isEmpty else { return .stay }
        return popping(to: stack.count - 1, in: stack)
    }

    public static func reopening(stack: [ChatStackEntry]) -> [ChatTarget] {
        stack.map(\.target)
    }

    private static func popping(to count: Int, in stack: [ChatStackEntry]) -> ChatNavigationStep {
        .show(path: stack.prefix(count).map(\.route), closing: stack.dropFirst(count).map(\.target))
    }
}
