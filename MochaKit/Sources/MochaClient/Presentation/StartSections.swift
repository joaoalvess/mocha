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
    public static let activeKinds: Set<HomeSectionKind> = [.needsYou, .working]

    public static func active(_ sections: [HomeSection]) -> [HomeSection] {
        sections.filter { activeKinds.contains($0.kind) }
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
