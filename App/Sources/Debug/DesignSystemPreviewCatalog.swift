#if DEBUG
import MochaClient
import SwiftUI

struct DesignSystemPreviewColors: View {
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
        ("glass", Palette.glass, "#3C3C3C"),
        ("composer", Palette.composer, "#383838"),
        ("controlBg", Palette.controlBg, "#202225"),
        ("controlSel", Palette.controlSel, "#121416"),
        ("claude", Palette.claude, "#D87454"),
        ("gitAccent", Palette.gitAccent, "#FB923C"),
        ("statusOk", Palette.statusOk, "#00FF00"),
        ("dirty", Palette.dirty, "#F4B450"),
        ("error", Palette.error, "#D8383C"),
        ("termText", Palette.termText, "#D4D8E0"),
        ("accessoryBar", Palette.accessoryBar, "#424242"),
        ("accessoryKey", Palette.accessoryKey, "#272829"),
        ("black", Palette.black, "#010102"),
        ("toolBorder", Palette.toolBorder, "#303438"),
        ("badgeOk", Palette.badgeOk, "#0F3712"),
        ("badgeWarn", Palette.badgeWarn, "#342C1F"),
        ("sepDot", Palette.sepDot, "#55595F"),
        ("ringTrack", Palette.ringTrack, "#2F3032"),
        ("divider", Palette.divider, "#202223"),
        ("barTrack", Palette.barTrack, "#191B1D"),
        ("paceMark", Palette.paceMark, "#979899"),
        ("claudeTile", Palette.claudeTile, "#2E221F"),
        ("heroBg", Palette.heroBg, "#120A08"),
        ("heroTile", Palette.heroTile, "#2E1914"),
        ("tableBorder", Palette.tableBorder, "#2B2B2B"),
        ("codeInner", Palette.codeInner, "#17191B"),
        ("grabber", Palette.grabber, "#47474B"),
    ]

    private static let screenTokens: [(String, Color, String)] = [
        ("glyphOnAccent", Palette.glyphOnAccent, "#000000"),
        ("glyphOnDirty", Palette.glyphOnDirty, "#1A1206"),
        ("sendDisabled", Palette.sendDisabled, "#49494B"),
        ("usageFootnote", Palette.usageFootnote, "#6F747B"),
        ("headerButton", Palette.headerButton, "#9BA0AA"),
        ("archivedTitle", Palette.archivedTitle, "#C9CCD0"),
        ("offlineRing", Palette.offlineRing, "#4A4E54"),
        ("offlineRingGlyph", Palette.offlineRingGlyph, "#101112"),
        ("offlineBadge", Palette.offlineBadge, "#1B1D1F"),
        ("offlineBadgeText", Palette.offlineBadgeText, "#8C939A"),
        ("offlineClaude", Palette.offlineClaude, "#8A6A5E"),
        ("destructive", Palette.destructive, "#F0555A"),
        ("stateBadgeOk", Palette.stateBadgeOk, "#0F2E07"),
        ("stateBadgeWarn", Palette.stateBadgeWarn, "#2A1E0D"),
        ("hostTile", Palette.hostTile, "#1C2A1E"),
        ("offlineCapsuleText", Palette.offlineCapsuleText, "#D0D3D7"),
        ("drawerHint", Palette.drawerHint, "#5F646B"),
        ("ctaText", Palette.ctaText, "#0A0A0A"),
        ("pairingLogoTop", Palette.pairingLogoTop, "#221813"),
        ("pairingLogoBottom", Palette.pairingLogoBottom, "#130D0B"),
        ("cameraSubtitle", Palette.cameraSubtitle, "#C9CCD1"),
    ]

    private static let glasses: [(String, GlassTint, String)] = [
        ("glassChat", .chat, "rgba(66,66,66,.8)"),
        ("glassComposer", .composer, "rgba(62,62,62,.84)"),
        ("glassHome", .home, "rgba(62,78,64,.5)"),
        ("glassPill", .pill, "rgba(96,100,106,.5)"),
        ("glassHero", .hero, "rgba(84,74,72,.5)"),
        ("glassBlack", .black, "rgba(60,60,62,.55)"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                swatchGrid(Self.tokens)
                SectionHeader(title: "Cores das telas")
                    .padding(.horizontal, -Metrics.contentMargin)
                swatchGrid(Self.screenTokens)
                SectionHeader(title: "Vidros sobre o brilho da Home")
                    .padding(.horizontal, -Metrics.contentMargin)
                ZStack {
                    HomeBackground()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(Self.glasses, id: \.0) { name, tint, detail in
                            swatch(name: name, detail: detail) {
                                Color.clear.mochaGlass(tint, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(Metrics.contentMargin)
        }
        .background(Palette.bg.ignoresSafeArea())
    }

    private func swatchGrid(_ tokens: [(String, Color, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(tokens, id: \.0) { name, color, hex in
                swatch(name: name, detail: hex) {
                    RoundedRectangle(cornerRadius: 6).fill(color)
                }
            }
        }
    }

    private func swatch(name: String, detail: String, @ViewBuilder fill: () -> some View) -> some View {
        HStack(spacing: 8) {
            fill()
                .frame(width: 40, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.textSecondary.opacity(0.3), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(Typography.mono(11, .bold, relativeTo: .caption))
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.mono(10, relativeTo: .caption2))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

struct DesignSystemPreviewTypography: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Build limpo. Agora os testes: \(Text("ASAuthorizationControllerDelegate").foregroundStyle(Palette.link)) e \(Text("negrito").bold()).")
                    .chatBodyStyle()
                Text("Brewed for 45s")
                    .chatText(.italic)
                    .foregroundStyle(Palette.textSecondary)
                Text("\(Text("Recap:").bold()) Você pediu login com a Apple no worktree login-social.")
                    .chatText(.italic)
                    .foregroundStyle(Palette.textSecondary)
                Text("Login com a Apple").font(Typography.headerTitle).foregroundStyle(Palette.textPrimary)
                Text("login-social • opus-5-5 • feat/login-social").font(Typography.headerSubtitle).foregroundStyle(Palette.textSecondary)
                Text("3003 0O 1lI {} #4293 -> != ...").chatBodyStyle()
                Text("Precisa de você").systemText(.sectionHeader).textCase(.uppercase).foregroundStyle(Palette.textSecondary)
                Text("Posso rodar npm run build?").systemText(.cardTitle).foregroundStyle(Palette.textPrimary)
                Text("Shell: swift test --filter AppleSignIn").systemText(.cardSubtitle).foregroundStyle(Palette.textSecondary)
                Text("Uso").systemText(.sheetTitle).foregroundStyle(Palette.textPrimary)
                Text("Perfil de provisionamento").systemText(.sheetRowLabel).foregroundStyle(Palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.contentMargin)
        }
        .background(Palette.bg.ignoresSafeArea())
    }
}

struct DesignSystemPreviewComponents: View {
    @State private var draft = "rodar os testes de novo"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group("Disco de status") {
                    HStack(spacing: 22) {
                        StatusDot(indicator: .agent(.idle))
                        StatusDot(indicator: .agent(.working))
                        StatusDot(indicator: .agent(.blocked))
                        StatusDot(indicator: .agent(.unknown))
                        StatusDot(indicator: .disconnected)
                        StatusDot(indicator: .archived)
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
                group("Anel de contexto") {
                    HStack(spacing: 12) {
                        ContextRing(percent: 62, style: .ready)
                        ContextRing(percent: 100, style: .ready)
                        ContextRing(percent: 71, style: .working)
                        ContextRing(percent: 58, style: .blocked)
                        ContextRing(percent: 47, style: .archived)
                        ContextRing(percent: 58, style: .offline)
                        ContextRing(percent: nil, style: .ready)
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
                group("Selos") {
                    HStack(spacing: 8) {
                        Badge(text: "login-social")
                        Badge(text: "site-pessoal", tone: .warning)
                        Badge(text: "demo-app", tone: .offline)
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
                group("Selos de estado") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            StateBadge(style: .working)
                            StateBadge(style: .ready)
                        }
                        HStack(spacing: 10) {
                            StateBadge(style: .needsYou)
                            StateBadge(style: .ended)
                        }
                    }
                    .padding(Metrics.contentMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.heroBg)
                }
                group("Botões redondos de vidro") {
                    ZStack {
                        HomeBackground()
                        HStack(spacing: 16) {
                            GlassRoundButton(systemImage: "arrow.down.to.line", accessibilityLabel: "Ir para o fim", style: .chat) {}
                            GlassRoundButton(icon: .sidebar, accessibilityLabel: "Gaveta", style: .home) {}
                            GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .hero) {}
                            GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .black) {}
                        }
                    }
                    .frame(height: 80)
                    .clipped()
                }
                group("Barras de uso e alça") {
                    VStack(alignment: .leading, spacing: 14) {
                        UsageBar(fraction: 0.12, paceFraction: 0.28).frame(width: 153.7)
                        UsageBar(fraction: 0.71, paceFraction: 0.94).frame(width: 153.7)
                        UsageBar(fraction: 0.71, height: 4).frame(width: 120)
                        SheetGrabber()
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
                group("Chat") {
                    VStack(alignment: .leading, spacing: 12) {
                        SlashChip(command: "/clear")
                        UserBubble(text: "ok")
                        UserBubble(text: "quando terminar, roda também o golangci-lint", delivery: .sending)
                        UserBubble(text: "e o lint?", delivery: .unconfirmed)
                        ToolCallCard(icon: .shell, name: "Shell", count: 1, summary: "go test ./internal/... -run Pagination -count=1", status: .running)
                        ToolCallCard(icon: .sparkles, name: "Grep", count: 1, summary: "\"OFFSET\" internal/", status: .succeeded)
                        ToolCallCard(icon: .shell, name: "Shell", count: 3, summary: "xcodebuild -scheme DemoApp", status: .failed)
                        CollapsedComposer(draft: draft)
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
                group("Subagentes e workflows") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            LineIconView(icon: .agent, size: 15, strokeWidth: 1.9, color: Palette.textSecondary)
                            LineIconView(icon: .agent, size: 15, strokeWidth: 2.1, color: Palette.claude)
                            LineIconView(icon: .flow, size: 15, strokeWidth: 1.9, color: Palette.textSecondary)
                            LineIconView(icon: .stopCircle, size: 15, strokeWidth: 2, color: Palette.textSecondary)
                        }
                        HStack(spacing: 16) {
                            SubagentStateIcon(status: .running)
                            SubagentStateIcon(status: .completed)
                            SubagentStateIcon(status: .failed)
                            SubagentStateIcon(status: .stopped)
                        }
                        HStack(spacing: 16) {
                            SubagentStateIcon(status: .running, size: 16)
                            SubagentStateIcon(status: .completed, size: 16)
                            SubagentStateIcon(status: .failed, size: 16)
                            SubagentStateIcon(status: .stopped, size: 16)
                        }
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
                group("Linhas de folha") {
                    SheetListCard {
                        SheetListRow(label: "Host", value: "MacBook", isCompact: true)
                        SheetListRow(label: "Workspace do Herdr", value: "login-social", valueStyle: .mono, isCompact: true)
                        SheetListRow(label: "Perfil de provisionamento", value: "vence em 5 dias", valueStyle: .warning)
                    }
                    .padding(.horizontal, Metrics.contentMargin)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Palette.bg.ignoresSafeArea())
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title)
            content()
        }
    }
}
#endif
