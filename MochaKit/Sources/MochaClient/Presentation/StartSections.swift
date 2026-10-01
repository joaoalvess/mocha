import Foundation
import MochaProtocol

public struct RecentThumbnail: Sendable, Hashable {
    public var userText: String?
    public var assistantText: String?
    public var toolName: String?
    public var toolSummary: String?

    public init(userText: String? = nil, assistantText: String? = nil, toolName: String? = nil, toolSummary: String? = nil) {
        self.userText = userText
        self.assistantText = assistantText
        self.toolName = toolName
        self.toolSummary = toolSummary
    }

    init(preview: MessagePreview?, activity: ToolActivity?) {
        switch preview?.author {
        case .user?: userText = preview?.text
        case .assistant?: assistantText = preview?.text
        case nil: break
        }
        toolName = activity.map { ToolPresentation.displayName(for: $0.toolName) }
        toolSummary = activity?.summary
    }
}

public struct RecentItem: Sendable, Hashable, Identifiable {
    public var card: HomeCard
    public var thumbnail: RecentThumbnail

    public var id: ChatTarget { card.target }

    public var stateText: String {
        StartSections.stateText(for: card.state)
    }

    public init(card: HomeCard, thumbnail: RecentThumbnail) {
        self.card = card
        self.thumbnail = thumbnail
    }
}

public enum StartSections {
    public static let recentLimit = 10

    public static func open(agents: [AgentSummary], now: Date) -> [HomeCard] {
        let cards = agents
            .filter { $0.kind == HomeSections.claudeKind || $0.kind == HomeSections.codexKind }
            .map { HomeSections.card(for: $0, in: HomeSections.kind(of: $0, now: now), now: now) }
        return cards.enumerated()
            .sorted { lhs, rhs in
                let left = openRank(lhs.element.state)
                let right = openRank(rhs.element.state)
                guard left == right else { return left < right }
                let leftActivity = lhs.element.activityAt ?? .distantPast
                let rightActivity = rhs.element.activityAt ?? .distantPast
                return leftActivity == rightActivity ? lhs.offset < rhs.offset : leftActivity > rightActivity
            }
            .map(\.element)
    }

    private static func openRank(_ state: HomeCardState) -> Int {
        switch state {
        case .blocked: 0
        case .working: 1
        case .ready, .archived: 2
        }
    }

    public static func recents(agents: [AgentSummary], archived: [ArchivedSession], now: Date, limit: Int = recentLimit) -> [RecentItem] {
        var items: [RecentItem] = []
        for agent in agents where agent.kind == HomeSections.claudeKind || agent.kind == HomeSections.codexKind {
            let kind = HomeSections.kind(of: agent, now: now)
            items.append(RecentItem(
                card: HomeSections.card(for: agent, in: kind, now: now),
                thumbnail: RecentThumbnail(preview: agent.preview, activity: agent.activity)
            ))
        }
        for session in archived {
            items.append(RecentItem(
                card: HomeSections.card(for: session, now: now),
                thumbnail: RecentThumbnail(preview: session.preview, activity: nil)
            ))
        }
        let sorted = items.enumerated().sorted { lhs, rhs in
            let left = lhs.element.card.activityAt ?? .distantPast
            let right = rhs.element.card.activityAt ?? .distantPast
            return left == right ? lhs.offset < rhs.offset : left > right
        }
        return Array(sorted.prefix(max(0, limit)).map(\.element))
    }

    public static func stateText(for state: HomeCardState) -> String {
        switch state {
        case .blocked: "Precisa de você"
        case .working: "Trabalhando"
        case .ready: "Concluído"
        case .archived: "Arquivado"
        }
    }
}
