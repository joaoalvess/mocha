#if DEBUG
import MochaProtocol
import SwiftUI

enum DesignSystemPreviewSection: String, CaseIterable, Identifiable {
    case colors
    case typography
    case statusDot = "status-dot"
    case header
    case glassButton = "glass-button"
    case composer
    case toolCard = "tool-card"
    case bubble

    static let argumentKey = "preview-section"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colors: "Cores"
        case .typography: "Tipografia"
        case .statusDot: "Ponto de status"
        case .header: "Header de vidro"
        case .glassButton: "Botão redondo de vidro"
        case .composer: "Composer vazio"
        case .toolCard: "Card de ferramenta"
        case .bubble: "Bolha do usuário"
        }
    }
}

struct DesignSystemPreviewScreen: View {
    private let sections: [DesignSystemPreviewSection]

    init(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) {
        let requested = (argumentDomain[DesignSystemPreviewSection.argumentKey] as? String)
            .flatMap(DesignSystemPreviewSection.init(rawValue:))
        sections = requested.map { [$0] } ?? DesignSystemPreviewSection.allCases
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title.uppercased())
                            .font(Typography.drawerSectionHeader)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Metrics.contentMargin)
                        content(for: section)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Palette.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(for section: DesignSystemPreviewSection) -> some View {
        switch section {
        case .colors: ColorSwatches()
        case .typography: TypographySamples()
        case .statusDot: StatusDotSamples()
        case .header: HeaderSamples()
        case .glassButton: GlassButtonSamples()
        case .composer: ComposerSamples()
        case .toolCard: ToolCardSamples()
        case .bubble: BubbleSamples()
        }
    }
}

private struct ColorSwatches: View {
    private static let tokens: [(String, Color, String)] = [
        ("bg", Palette.bg, "#1E1E1E"),
        ("drawerBg", Palette.drawerBg, "#161719"),
        ("scrim", Palette.scrim, "#0F0F10"),
        ("textPrimary", Palette.textPrimary, "#FCFCFC"),
        ("textSecondary", Palette.textSecondary, "#98A0A8"),
        ("link", Palette.link, "#78A0F4"),
        ("userBubble", Palette.userBubble, "#1B351B"),
        ("selectedRow", Palette.selectedRow, "#142E16"),
        ("toolCard", Palette.toolCard, "#121416"),
        ("toolCardBorder", Palette.toolCardBorder, "#303438"),
        ("glass", Palette.glass, "#3C3C3C"),
        ("composer", Palette.composer, "#383838"),
        ("controlBg", Palette.controlBg, "#202225"),
        ("controlSelected", Palette.controlSelected, "#121416"),
        ("claude", Palette.claude, "#D87454"),
        ("gitAccent", Palette.gitAccent, "#FB923C"),
        ("statusOk", Palette.statusOk, "#00FF00"),
        ("dirty", Palette.dirty, "#F4B450"),
        ("error", Palette.error, "#D8383C"),
        ("termText", Palette.termText, "#D4D8E0"),
        ("accessoryBar", Palette.accessoryBar, "#424242"),
        ("accessoryKey", Palette.accessoryKey, "#272829"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            ForEach(Self.tokens, id: \.0) { name, color, hex in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: 40, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.textSecondary.opacity(0.3), lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(Typography.mono(11, .bold, relativeTo: .caption))
                            .foregroundStyle(Palette.textPrimary)
                        Text(hex)
                            .font(Typography.mono(11, relativeTo: .caption))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.contentMargin)
    }
}

private struct TypographySamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("O que faço com as alterações: \(Text("descarto").bold()), \(Text("salvo um patch").bold()) na scratchpad antes de remover, ou \(Text("commito").bold()) na \(Text("test/teste").foregroundStyle(Palette.link))? E posso seguir com a proposta?")
                .chatBodyStyle()
            Text("Negrito explícito: \(Text("descarto").font(Typography.chatBodyBold))")
                .chatBodyStyle()
            Text("Brewed for 45s")
                .font(Typography.chatItalic)
                .foregroundStyle(Palette.textSecondary)
            Text("\(Text("Recap:").font(Typography.chatBoldItalic)) Você pediu para eu ajustar o herdr-sidebar e depois encerrar o worktree de teste.")
                .font(Typography.chatItalic)
                .lineSpacing(Typography.chatLineSpacing)
                .foregroundStyle(Palette.textSecondary)
            Text("3003 0O 1lI {} #4293 -> != ...")
                .chatBodyStyle()
            Text("Gaveta: Developer • Claude: clear")
                .font(Typography.drawerRow)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Metrics.contentMargin)
    }
}

private struct StatusDotSamples: View {
    private static let samples: [(String, StatusIndicator)] = [
        ("idle", .agent(.idle)),
        ("done", .agent(.done)),
        ("working", .agent(.working)),
        ("blocked", .agent(.blocked)),
        ("unknown", .agent(.unknown)),
        ("sem conexão", .disconnected),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Self.samples, id: \.0) { label, indicator in
                VStack(spacing: 6) {
                    StatusDot(indicator: indicator)
                    Text(label)
                        .font(Typography.mono(10, relativeTo: .caption2))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, Metrics.contentMargin)
    }
}

private struct HeaderSamples: View {
    var body: some View {
        VStack(spacing: 16) {
            header(.agent(.idle))
            header(.agent(.working))
            header(.disconnected)
        }
    }

    private func header(_ indicator: StatusIndicator) -> some View {
        ZStack(alignment: .top) {
            GlassBackdrop()
            ChatHeaderBar(
                indicator: indicator,
                title: "herdr-sidebar abre arquivos em nova tab",
                subtitle: ChatSubtitle.text(workspace: "Core", model: "claude-opus-5-5", branch: "development"),
                onOpenDrawer: {}
            )
            .padding(.horizontal, Metrics.floatingMargin)
            .padding(.top, 8)
        }
    }
}

private struct GlassButtonSamples: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            GlassBackdrop()
            GlassRoundButton(systemImage: "arrow.down.to.line", accessibilityLabel: "Ir para o fim") {}
                .padding(.trailing, Metrics.floatingMargin)
        }
    }
}

private struct ComposerSamples: View {
    @State private var empty = ""
    @State private var printLike = ""
    @State private var typed = "rodar os testes de novo"
    @State private var working = ""

    var body: some View {
        VStack(spacing: 16) {
            sample(ComposerBar(text: $empty))
            sample(ComposerBar(text: $printLike, showsTerminalButton: true))
            sample(ComposerBar(text: $typed))
            sample(ComposerBar(text: $working, mode: .stop))
        }
    }

    private func sample(_ composer: ComposerBar) -> some View {
        ZStack(alignment: .bottom) {
            GlassBackdrop()
            composer
                .padding(.horizontal, Metrics.floatingMargin)
                .padding(.bottom, 8)
        }
    }
}

private struct ToolCardSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToolCallCard(
                name: "Shell",
                count: 1,
                summary: "herdr worktree remove --workspace w18 2>&1 | sed -n 1,30p",
                status: .succeeded
            )
            ToolCallCard(
                name: "Shell",
                count: 3,
                summary: "ls -d /Users/joaoalves/Developer/initech/.claude/worktrees/teste && herdr workspace list | jq '{workspace_id,label}'",
                status: .failed
            )
            ToolCallCard(name: "Read", count: 1, summary: "App/Sources/AppShell/AppSession.swift", status: .running)
            ToolCallCard(
                name: "Shell",
                count: 1,
                summary: "swift test --filter DemoScriptTests",
                status: .succeeded,
                isExpanded: true
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("swift test --filter DemoScriptTests")
                        .font(Typography.toolCard)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Test run with 14 tests in 1 suite passed after 0.412 seconds.")
                        .font(Typography.toolCard)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Metrics.contentMargin)
    }
}

private struct BubbleSamples: View {
    var body: some View {
        VStack(spacing: 12) {
            UserBubble(text: "sao alteracoes de teste apenas so cancelar tudo e ja era")
            UserBubble(text: "ok")
        }
        .padding(.horizontal, Metrics.contentMargin)
    }
}

private struct GlassBackdrop: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("2. Rodar \(Text("docker compose down").foregroundStyle(Palette.link)) na raiz do worktree, sem \(Text("-v").foregroundStyle(Palette.link)).")
            Text("3. Fechar as tabs do workspace Teste.")
            Text("4. Conferir com \(Text("docker ps").foregroundStyle(Palette.link)) e \(Text("lsof").foregroundStyle(Palette.link)) que não sobrou nada.")
        }
        .chatBodyStyle()
        .padding(.horizontal, Metrics.contentMargin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
