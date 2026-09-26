#if DEBUG
import SwiftUI

enum DesignSystemPreviewSection: String, CaseIterable, Identifiable {
    case colors
    case typography
    case components
    case home
    case chat
    case chatExpanded = "chat-expanded"
    case chatWorking = "chat-working"
    case composer
    case usage
    case detail
    case settings

    static let argumentKey = "preview-section"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colors: "Cores e vidros"
        case .typography: "Tipografia"
        case .components: "Componentes e estados"
        case .home: "Home (02-home)"
        case .chat: "Chat (05-chat-inicio-turno)"
        case .chatExpanded: "Card expandido (06-card-expandido)"
        case .chatWorking: "Chat trabalhando (07-chat-trabalhando)"
        case .composer: "Composer expandido (08-chat-digitando)"
        case .usage: "Uso (03-uso-plano)"
        case .detail: "Detalhe (04-detalhe-agente)"
        case .settings: "Ajustes (12-ajustes)"
        }
    }
}

struct DesignSystemPreviewScreen: View {
    private let requested: DesignSystemPreviewSection?

    init(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) {
        requested = (argumentDomain[DesignSystemPreviewSection.argumentKey] as? String)
            .flatMap(DesignSystemPreviewSection.init(rawValue:))
    }

    var body: some View {
        if let requested {
            DesignSystemPreviewContent(section: requested)
        } else {
            NavigationStack {
                List(DesignSystemPreviewSection.allCases) { section in
                    NavigationLink(section.title, value: section)
                }
                .navigationTitle("Design system")
                .navigationDestination(for: DesignSystemPreviewSection.self) { section in
                    DesignSystemPreviewContent(section: section)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}

struct DesignSystemPreviewContent: View {
    let section: DesignSystemPreviewSection

    var body: some View {
        switch section {
        case .colors: DesignSystemPreviewColors()
        case .typography: DesignSystemPreviewTypography()
        case .components: DesignSystemPreviewComponents()
        case .home: DesignSystemPreviewHome()
        case .chat: DesignSystemPreviewChat()
        case .chatExpanded: DesignSystemPreviewChatExpanded()
        case .chatWorking: DesignSystemPreviewChatWorking()
        case .composer: DesignSystemPreviewComposer()
        case .usage: DesignSystemPreviewUsage()
        case .detail: DesignSystemPreviewDetail()
        case .settings: DesignSystemPreviewSettings()
        }
    }
}
#endif
