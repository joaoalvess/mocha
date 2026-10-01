import Foundation
import MochaProtocol

public enum HomeSectionKind: String, Sendable, CaseIterable, Identifiable {
    case needsYou
    case working
    case done
    case archived

    public var id: Self { self }

    public var title: String {
        switch self {
        case .needsYou: "Precisa de você"
        case .working: "Trabalhando"
        case .done: "Concluídos"
        case .archived: "Arquivados"
        }
    }
}

public enum HomeCardState: Sendable, Hashable {
    case blocked
    case working
    case ready
    case archived
}

public struct HomeCard: Sendable, Hashable, Identifiable {
    public var target: ChatTarget
    public var provider: AgentProvider
    public var state: HomeCardState
    public var title: String
    public var subtitle: String?
    public var subtitleIsWarning: Bool
    public var workspace: String
    public var contextLeftPercent: Int?
    public var activityAt: Date?
    public var time: String
    public var archiveSessionId: String?
    public var controlAvailable: Bool
    public var runningSubagents: Int

    public var id: ChatTarget { target }

    public var canArchive: Bool { archiveSessionId != nil }

    public var subagentBadge: String? {
        guard runningSubagents > 0 else { return nil }
        return runningSubagents == 1 ? "1 subagente" : "\(runningSubagents) subagentes"
    }

    public init(
        target: ChatTarget,
        provider: AgentProvider = .claude,
        state: HomeCardState,
        title: String,
        subtitle: String? = nil,
        subtitleIsWarning: Bool = false,
        workspace: String,
        contextLeftPercent: Int? = nil,
        activityAt: Date? = nil,
        time: String,
        archiveSessionId: String? = nil,
        controlAvailable: Bool = true,
        runningSubagents: Int = 0
    ) {
        self.target = target
        self.provider = provider
        self.state = state
        self.title = title
        self.subtitle = subtitle
        self.subtitleIsWarning = subtitleIsWarning
        self.workspace = workspace
        self.contextLeftPercent = contextLeftPercent
        self.activityAt = activityAt
        self.time = time
        self.archiveSessionId = archiveSessionId
        self.controlAvailable = controlAvailable
        self.runningSubagents = runningSubagents
    }
}

public struct HomeSection: Sendable, Hashable, Identifiable {
    public var kind: HomeSectionKind
    public var cards: [HomeCard]

    public var id: HomeSectionKind { kind }

    public init(kind: HomeSectionKind, cards: [HomeCard]) {
        self.kind = kind
        self.cards = cards
    }
}

public enum HomeSections {
    public static let claudeKind = "claude"
    public static let codexKind = "codex"
    public static let refreshInterval: TimeInterval = 30
    public static let idleArchiveDelay: TimeInterval = 10 * 60
    public static let sessionMaximumAge: TimeInterval = 6 * 60 * 60
    public static let emptySessionTitle = "Sessão limpa"
    public static let endedSessionSubtitle = "Sessão encerrada"
    public static let needsYouSubtitle = "Precisa de você"
    public static let unknownTime = "—"

    public static func make(agents: [AgentSummary], archived: [ArchivedSession], now: Date) -> [HomeSection] {
        var grouped: [HomeSectionKind: [HomeCard]] = [:]
        for agent in agents where agent.kind == claudeKind || agent.kind == codexKind {
            let kind = kind(of: agent, now: now)
            grouped[kind, default: []].append(card(for: agent, in: kind, now: now))
        }
        for session in archived {
            grouped[.archived, default: []].append(card(for: session, now: now))
        }
        return HomeSectionKind.allCases.compactMap { kind in
            guard let cards = grouped[kind], !cards.isEmpty else { return nil }
            return HomeSection(kind: kind, cards: sortedByRecency(cards))
        }
    }

    public static func kind(of agent: AgentSummary, now: Date) -> HomeSectionKind {
        switch agent.status {
        case .blocked:
            return .needsYou
        case .working:
            return .working
        case .idle, .done, .unknown:
            return isArchived(agent, now: now) ? .archived : .done
        }
    }

    public static func isArchived(_ agent: AgentSummary, now: Date) -> Bool {
        if agent.archivedAt != nil {
            return true
        }
        if (agent.runningSubagents ?? 0) > 0 {
            return false
        }
        if let startedAt = agent.sessionStartedAt, now.timeIntervalSince(startedAt) > sessionMaximumAge {
            return true
        }
        if let lastTurnAt = agent.turnEndedAt ?? agent.lastActivityAt, now.timeIntervalSince(lastTurnAt) >= idleArchiveDelay {
            return true
        }
        return false
    }

    public static func offlineProblem(for state: ConnectionState, previous: ConnectionProblem?) -> ConnectionProblem? {
        switch state {
        case .waitingToRetry(let problem), .failed(let problem):
            problem
        case .idle, .connecting:
            previous
        case .connected, .pairingRequired:
            nil
        }
    }

    public static func title(for preview: MessagePreview?) -> String {
        guard let preview else { return emptySessionTitle }
        switch preview.author {
        case .user: return "Você: " + preview.text
        case .assistant: return preview.text
        }
    }

    public static func card(for agent: AgentSummary, in kind: HomeSectionKind, now: Date) -> HomeCard {
        HomeCard(
            target: .agent(agent.id),
            provider: agent.kind == codexKind ? .codex : .claude,
            state: state(for: kind),
            title: title(for: agent.preview),
            subtitle: agent.kind == codexKind && agent.controlAvailable == false ? "Controle indisponível" : subtitle(for: agent, in: kind),
            subtitleIsWarning: kind == .needsYou,
            workspace: agent.workspaceLabel,
            contextLeftPercent: agent.contextLeftPercent,
            activityAt: agent.lastActivityAt,
            time: timeText(agent.lastActivityAt, now: now),
            archiveSessionId: kind == .done ? agent.sessionId : nil,
            controlAvailable: agent.kind != codexKind || agent.controlAvailable == true,
            runningSubagents: max(0, agent.runningSubagents ?? 0)
        )
    }

    public static func card(for session: ArchivedSession, now: Date) -> HomeCard {
        let activityAt = session.lastActivityAt ?? session.endedAt
        return HomeCard(
            target: session.provider == .codex ? .codexThread(session.id) : .session(session.id),
            provider: session.provider,
            state: .archived,
            title: title(for: session.preview),
            subtitle: endedSessionSubtitle,
            workspace: session.workspaceLabel,
            contextLeftPercent: session.contextLeftPercent,
            activityAt: activityAt,
            time: timeText(activityAt, now: now)
        )
    }

    private static func state(for kind: HomeSectionKind) -> HomeCardState {
        switch kind {
        case .needsYou: .blocked
        case .working: .working
        case .done: .ready
        case .archived: .archived
        }
    }

    private static func subtitle(for agent: AgentSummary, in kind: HomeSectionKind) -> String? {
        switch kind {
        case .needsYou:
            guard let activity = agent.activity else { return needsYouSubtitle }
            return needsYouSubtitle + " · " + ToolPresentation.displayName(for: activity.toolName)
        case .working:
            guard let activity = agent.activity else { return nil }
            return ToolPresentation.displayName(for: activity.toolName) + ": " + activity.summary
        case .done, .archived:
            return nil
        }
    }

    private static func timeText(_ date: Date?, now: Date) -> String {
        guard let date else { return unknownTime }
        return RelativeTime.text(from: date, now: now)
    }

    private static func sortedByRecency(_ cards: [HomeCard]) -> [HomeCard] {
        cards.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.activityAt ?? .distantPast
                let right = rhs.element.activityAt ?? .distantPast
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }
}

public enum HomeCardSwipeDirection: Sendable, Hashable {
    case left
    case right
}

public enum HomeCardSwipe {
    public static let actionWidthFraction = 0.4
    public static let projectionTime = 0.2

    public static func begins(velocityX: Double, velocityY: Double, directions: Set<HomeCardSwipeDirection> = [.left]) -> Bool {
        guard velocityX != 0, abs(velocityX) > abs(velocityY) else { return false }
        return directions.contains(velocityX < 0 ? .left : .right)
    }

    public static func offset(forTranslation translation: Double, directions: Set<HomeCardSwipeDirection> = [.left]) -> Double {
        let lower = directions.contains(.left) ? -Double.infinity : 0
        let upper = directions.contains(.right) ? Double.infinity : 0
        return min(upper, max(lower, translation))
    }

    public static func triggeredDirection(translation: Double, velocity: Double, width: Double) -> HomeCardSwipeDirection? {
        guard width > 0, translation != 0 else { return nil }
        let projected = translation + velocity * projectionTime
        guard (projected < 0) == (translation < 0), abs(projected) >= width * actionWidthFraction else { return nil }
        return translation < 0 ? .left : .right
    }

    public static func revealsAction(offset: Double, width: Double) -> Bool {
        width > 0 && abs(offset) >= width * actionWidthFraction
    }
}

public enum SessionIdFormat {
    public static let headLength = 13
    public static let tailLength = 12

    public static func shortened(_ sessionId: String) -> String {
        guard sessionId.count > headLength + tailLength + 1 else { return sessionId }
        return String(sessionId.prefix(headLength)) + "…" + String(sessionId.suffix(tailLength))
    }
}
