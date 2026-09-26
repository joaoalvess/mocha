#if DEBUG
import MochaClient
import MochaProtocol
import SwiftUI

struct DesignSystemPreviewHome: View {
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                SectionHeader(title: "Precisa de você")
                card(
                    ring: ContextRing(percent: 58, style: .blocked),
                    isWarning: true,
                    content: HomeCardContent(
                        title: "Posso rodar npm run build para validar o feed?",
                        subtitle: "Precisa de você · Shell",
                        subtitleIsWarning: true,
                        workspace: "site-pessoal",
                        time: "há 1 min"
                    )
                )
                SectionHeader(title: "Trabalhando", topPadding: Metrics.sectionHeaderTopAfterCard)
                card(
                    ring: ContextRing(percent: 71, style: .working),
                    content: HomeCardContent(
                        title: "Você: implementa login com a Apple nesse worktree…",
                        subtitle: "Shell: swift test --filter AppleSignIn",
                        workspace: "login-social",
                        time: "agora"
                    )
                )
                card(
                    ring: ContextRing(percent: 84, style: .working),
                    content: HomeCardContent(title: "Troquei o OFFSET por cursor em ListRecipes. Ag…", workspace: "receitas-api", time: "há 2 min")
                )
                SectionHeader(title: "Concluídos", topPadding: Metrics.sectionHeaderTopAfterCard)
                card(
                    ring: ContextRing(percent: 62, style: .ready),
                    content: HomeCardContent(title: "Os testes da tela de ajustes passaram. Quer que…", workspace: "demo-app", time: "há 6 min")
                )
                card(
                    ring: ContextRing(percent: 100, style: .ready),
                    content: HomeCardContent(title: "Sessão limpa", workspace: "receitas-api", time: "há 4 min")
                )
                SectionHeader(title: "Arquivados", topPadding: Metrics.sectionHeaderTopAfterCard)
                card(
                    ring: ContextRing(percent: 47, style: .archived),
                    content: HomeCardContent(
                        title: "Você: cria o worktree login-social a partir da main",
                        subtitle: "Sessão encerrada",
                        workspace: "login-social",
                        time: "ontem",
                        tone: .archived
                    )
                )
                card(
                    ring: ContextRing(percent: 90, style: .archived),
                    content: HomeCardContent(
                        title: "Você: revisa o README antes do release",
                        subtitle: "Sessão encerrada",
                        workspace: "demo-app",
                        time: "ontem",
                        tone: .archived
                    )
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Metrics.homeListTopInset)
            PreviewHomeButtons()
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background { HomeBackground() }
    }

    private func card(ring: ContextRing, isWarning: Bool = false, content: HomeCardContent) -> some View {
        HomeCardFrame(isWarning: isWarning) { ring } content: { content }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.bottom, Metrics.homeCardSpacing)
    }
}

struct DesignSystemPreviewChat: View {
    var body: some View {
        PreviewChatScreen(indicator: .agent(.idle), title: "Login com a Apple", subtitle: PreviewText.loginSubtitle) {
            PreviewChatColumn(topInset: 75) {
                SlashChip(command: "/clear")
                PreviewNotice(text: "Sessão nova · 13:44 · opus-5-5")
                UserBubble(text: "implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain")
                PreviewThinking(text: "Pensou: Preciso entender o AuthService atual antes. E o entitlement de Sign in with Apple…")
                PreviewTools {
                    ToolCallCard(icon: .document, name: "Read", count: 2, summary: "Auth/AuthService.swift", status: .succeeded)
                    ToolCallCard(icon: .pencil, name: "Edit", count: 1, summary: "DemoApp.entitlements", status: .succeeded)
                    ToolCallCard(icon: .shell, name: "Shell", count: 3, summary: "xcodebuild -scheme DemoApp -destination 'generic/platform=iOS'", status: .failed)
                }
                PreviewParagraph(text: Text("O build falhou: faltam os métodos de \(PreviewText.code("ASAuthorizationControllerDelegate")), que precisam ser \(PreviewText.code("nonisolated")). Corrigindo."))
                PreviewTools {
                    ToolCallCard(icon: .pencil, name: "Edit", count: 1, summary: "Auth/AppleSignInCoordinator.swift", status: .succeeded)
                    ToolCallCard(icon: .shell, name: "Shell", count: 1, summary: "xcodebuild -scheme DemoApp build", status: .succeeded)
                }
                PreviewParagraph(text: Text("Build limpo. Agora os testes:"))
                PreviewTools {
                    ToolCallCard(icon: .shell, name: "Shell", count: 1, summary: "swift test --filter AppleSignIn", status: .succeeded)
                }
                PreviewParagraph(text: Text("Os 6 testes passaram, inclusive o de token expirado."))
            }
        }
    }
}

struct DesignSystemPreviewChatExpanded: View {
    var body: some View {
        PreviewChatScreen(indicator: .agent(.idle), title: "Login com a Apple", subtitle: PreviewText.loginSubtitle, showsDownButton: true) {
            PreviewChatColumn(topInset: 13) {
                PreviewParagraph(text: Text("de ponta a ponta, sem nenhum mock do Keychain no caminho feliz."))
                PreviewParagraph(text: Text("Enquanto a suíte roda, reviso o coordinator."))
                PreviewTools {
                    ToolCallCard(icon: .shell, name: "Shell", count: 2, summary: "swift test --filter AppleSignIn 2>&1 | tail -20", status: .succeeded)
                    ToolCallCard(icon: .sparkles, name: "Background task", count: 1, summary: "swift test (exit code 0)", status: .succeeded)
                }
                ToolCallCard(icon: .shell, name: "Shell", count: 1, summary: "cat /private/tmp/…/b7k2q.output", status: .succeeded, isExpanded: true) {
                    ToolCallDetailBox(input: "cat /private/tmp/claude-501/demo-app/tasks/b7k2q.output", output: PreviewText.testOutput)
                }
                PreviewThinking(text: "Pensou: Todos os testes passaram; falta conferir o entitlement…")
                PreviewTools {
                    ToolCallCard(icon: .shell, name: "Shell", count: 2, summary: "git add -A && git commit -m \"feat(auth): sign in with Apple\"", status: .succeeded)
                }
                PreviewParagraph(text: Text("Login com a Apple está pronto e commitado em \(PreviewText.code("feat/login-social")). Quer que eu abra o PR?"))
            }
        }
    }
}

struct DesignSystemPreviewChatWorking: View {
    var body: some View {
        PreviewChatScreen(indicator: .agent(.working), title: "Paginação por cursor em /receitas", subtitle: "receitas-api • opus-5-5 • development") {
            PreviewChatColumn(bottomInset: 73) {
                UserBubble(text: "troca a paginação de /receitas para cursor. mantém o formato da resposta")
                PreviewThinking(text: "Pensou")
                PreviewParagraph(text: Text("A listagem usa \(PreviewText.code("LIMIT/OFFSET")); com 40 mil receitas a página 200 leva 1,8 s. Cursor resolve sem mudar o contrato."))
                PreviewTools {
                    ToolCallCard(icon: .shell, name: "Shell", count: 2, summary: "rg -n \"OFFSET\" internal/", status: .succeeded)
                    ToolCallCard(icon: .document, name: "Read", count: 1, summary: "internal/recipes/handler.go", status: .succeeded)
                }
                PreviewParagraph(text: Text("Vou usar um cursor opaco em base64 com ordenação estável por id."))
                PreviewTools {
                    ToolCallCard(icon: .document, name: "Read", count: 2, summary: "internal/recipes/store.go", status: .succeeded)
                    ToolCallCard(icon: .pencil, name: "Edit", count: 3, summary: "internal/recipes/store.go", status: .succeeded)
                }
                PreviewParagraph(text: Text("Troquei o \(PreviewText.code("OFFSET")) por cursor em \(PreviewText.code("ListRecipes")) e ajustei o handler. Rodando os testes de integração:"))
                PreviewTools {
                    ToolCallCard(icon: .shell, name: "Shell", count: 1, summary: "go test ./internal/... -run Pagination -count=1", status: .running)
                }
                UserBubble(text: "quando terminar, roda também o golangci-lint", delivery: .sending)
                Color.clear.frame(height: 20)
            }
        }
    }
}

struct DesignSystemPreviewComposer: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()
            PreviewChatColumn(bottomInset: 395) {
                PreviewParagraph(text: Text("Build limpo. Agora os testes:"))
                PreviewTools {
                    ToolCallCard(icon: .shell, name: "Shell", count: 2, summary: "swift test --filter AppleSignIn", status: .succeeded)
                }
                PreviewParagraph(text: Text("O login volta para a Home sem piscar e a sessão sobrevive a um relaunch."))
                PreviewParagraph(text: Text("Os 6 testes passaram, inclusive o de token expirado."))
                PreviewItalic(text: Text("Brewed for 45s"))
                PreviewItalic(text: Text("\(Text("Recap:").bold()) Você pediu login com a Apple no worktree login-social. Está pronto e testado."))
            }
            ExpandedComposer(canSend: true, buttons: [.attach, .slashMenu, .microphone]) {
                Text("agora adiciona um teste para quando o usuário cancela o login no meio\(Text("▏").foregroundStyle(Palette.statusOk))")
                    .font(Typography.composer)
                    .lineSpacing(Typography.lineSpacing(size: Typography.composerSize, pitch: 20))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Metrics.floatingMargin)
            .padding(.bottom, 274)
            VStack {
                ChatHeaderBar(indicator: .agent(.idle), title: "Login com a Apple", subtitle: PreviewText.loginSubtitle)
                    .padding(.horizontal, Metrics.floatingMargin)
                    .padding(.top, Metrics.headerTopInset)
                Spacer()
            }
        }
    }
}

struct DesignSystemPreviewUsage: View {
    var body: some View {
        ZStack(alignment: .top) {
            DesignSystemPreviewHome()
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    SheetGrabber()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Uso")
                            .systemText(.sheetTitle)
                            .systemLinePitch(22, size: 17)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Text("atualizado há 4 min")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal, 21)
                    .padding(.top, 46)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 13.3) {
                        PreviewTile(background: Palette.claudeTile, size: 40, radius: 11) {
                            ClaudeMark(size: 25)
                        }
                        VStack(alignment: .leading, spacing: 3.5) {
                            Text("Max 20x (d•••@e•••.com)")
                                .systemText(.cardTitle)
                                .systemLinePitch(21, size: 16)
                                .foregroundStyle(Palette.textPrimary)
                            Text("Claude Code · MacBook")
                                .font(.system(size: 12))
                                .systemLinePitch(16, size: 12)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 66)
                    Rectangle().fill(Palette.divider).frame(height: 1)
                    VStack(spacing: 0) {
                        PreviewUsageRow(label: "5h", fraction: 0.12, pace: 0.28, remaining: "3h 35m")
                        PreviewUsageRow(label: "7d", fraction: 0.71, pace: 0.94, remaining: "2d 10h")
                    }
                    .padding(.top, 8.7)
                    .padding(.leading, 16)
                    .padding(.trailing, 17.3)
                    Text("5h: ritmo mais lento · 7d: ritmo mais lento")
                        .font(.system(size: 14))
                        .systemLinePitch(20, size: 14)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 9)
                        .padding(.bottom, 10)
                }
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Palette.toolCard))
                .padding(.horizontal, 20)
                .padding(.top, 19.3)
                Text("Os números vêm do último turno do Claude no Mac e ficam velhos quando não há turnos. O traço cinza marca onde o uso estaria num ritmo constante até o fim da janela.")
                    .font(.system(size: 12))
                    .systemLinePitch(17, size: 12)
                    .foregroundStyle(Palette.usageFootnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 22)
                Spacer()
            }
            .background(
                UnevenRoundedRectangle(topLeadingRadius: Metrics.sheetCornerRadius, topTrailingRadius: Metrics.sheetCornerRadius)
                    .fill(Palette.drawerBg)
                    .ignoresSafeArea(edges: .bottom)
            )
            .padding(.top, 325)
        }
    }
}

struct DesignSystemPreviewDetail: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            HomeBackground()
            UnevenRoundedRectangle(topLeadingRadius: Metrics.sheetCornerRadius, topTrailingRadius: Metrics.sheetCornerRadius)
                .fill(Palette.black)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    PreviewTile(background: Palette.heroTile, size: 80, radius: 22) {
                        ClaudeMark(size: 48)
                    }
                    Text("Você: implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.35)
                        .lineHeight(.exact(points: 28))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.top, 16.7)
                    Text("\(Text("login-social").font(Typography.mono(15)).foregroundStyle(Palette.statusOk)) · MacBook · agora")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 7.9)
                    StateBadge(style: .working)
                        .padding(.top, 15.4)
                }
                .padding(.horizontal, 26)
                .padding(.top, 23.7)
                .padding(.bottom, 24.3)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.heroBg))
                Color.clear.frame(height: 72.3)
                VStack(alignment: .leading, spacing: 3.7) {
                    HStack {
                        Text("Conta")
                        Spacer()
                        Text("Max 20x (d•••@e•••.com)")
                    }
                    .font(.system(size: 14))
                    .systemLinePitch(20, size: 14)
                    .foregroundStyle(Palette.textSecondary)
                    VStack(spacing: 0) {
                        PreviewAccountRow(label: "5h", fraction: 0.12, remaining: "3h 35m")
                        PreviewAccountRow(label: "7d", fraction: 0.71, remaining: "2d 10h")
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 16.3)
                .padding(.trailing, 16.7)
                .frame(height: 91.7, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.toolCard))
                .padding(.top, 20.3)
                SheetListCard {
                    SheetListRow(label: "Host", value: "MacBook", isCompact: true)
                    SheetListRow(label: "Modelo", value: "opus-5-5", isCompact: true)
                    SheetListRow(label: "Workspace do Herdr", value: "login-social", valueStyle: .mono, isCompact: true)
                    SheetListRow(label: "Tab do Herdr", value: "Claude", valueStyle: .mono, isCompact: true)
                    SheetListRow(label: "Sessão", value: "b3e8d1f0-2c4a…7a5c3e2b0d9f", valueStyle: .mono, isCompact: true) {
                        LineIconView(icon: .copy, size: 16, strokeWidth: 1.8, color: Palette.textSecondary)
                    }
                }
                .padding(.top, 16.3)
            }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.top, 4)
            GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .hero) {}
                .padding(.leading, 16)
                .padding(.top, 16)
        }
    }
}

struct DesignSystemPreviewSettings: View {
    var body: some View {
        ZStack(alignment: .top) {
            HomeBackground()
            UnevenRoundedRectangle(topLeadingRadius: Metrics.sheetCornerRadius, topTrailingRadius: Metrics.sheetCornerRadius)
                .fill(Palette.black)
                .ignoresSafeArea(edges: .bottom)
            Text("Ajustes")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 27)
            HStack {
                GlassRoundButton(systemImage: "xmark", accessibilityLabel: "Fechar", style: .black) {}
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 0) {
                PreviewSheetLabel(text: "Mac pareado")
                SheetListCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 13) {
                            PreviewTile(background: Palette.hostTile, size: 40, radius: 11) {
                                LineIconView(icon: .laptop, size: 25, strokeWidth: 1.9, color: Palette.statusOk)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("MacBook-Pro.local")
                                    .systemText(.cardTitle)
                                    .systemLinePitch(21, size: 16)
                                    .foregroundStyle(Palette.textPrimary)
                                Text("via Tailscale · pareado em 24/09")
                                    .font(.system(size: 13))
                                    .systemLinePitch(17, size: 13)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        SheetListRow(label: "Conexão", value: "Conectado", valueDot: Palette.statusOk)
                    }
                    SheetListRow(label: "Herdr", value: "conectado ao mochad")
                }
                Color.clear.frame(height: 26)
                PreviewSheetLabel(text: "Notificações", detail: "· 1a-final")
                SheetListCard {
                    SheetListRow(label: "Turno concluído", value: nil) {
                        Toggle("Turno concluído", isOn: .constant(true))
                            .labelsHidden()
                            .tint(Palette.statusOk)
                    }
                }
                SheetFootnote(text: Text("Avisa quando o Claude termina um turno e o chat dele não está aberto. Pedidos de aprovação sempre avisam."))
                Color.clear.frame(height: 26)
                PreviewSheetLabel(text: "Este iPhone")
                SheetListCard {
                    SheetListRow(label: "Perfil de provisionamento", value: "vence em 5 dias", valueStyle: .warning)
                    SheetListRow(label: "Versão do app", value: "0.1.0 (14)", valueStyle: .mono)
                    SheetListRow(label: "Versão do daemon", value: "mochad 0.1.0", valueStyle: .mono)
                }
                Color.clear.frame(height: 26)
                SheetListCard {
                    Text("Desparear este iPhone")
                        .systemText(.sheetRowAction)
                        .foregroundStyle(Palette.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                SheetFootnote(text: Text("Apaga o token do Keychain e avisa o Mac. Para voltar, rode \(Text("mochad pair").font(Typography.mono(12, relativeTo: .caption)).foregroundStyle(Palette.link))."))
            }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.top, 77)
        }
    }
}

private struct PreviewChatScreen<Content: View>: View {
    let indicator: StatusIndicator
    let title: String
    let subtitle: String
    var showsDownButton = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            content()
            VStack(spacing: 0) {
                ChatHeaderBar(indicator: indicator, title: title, subtitle: subtitle)
                    .padding(.horizontal, Metrics.floatingMargin)
                    .padding(.top, Metrics.headerTopInset)
                Spacer()
                if showsDownButton {
                    GlassRoundButton(systemImage: "arrow.down.to.line", accessibilityLabel: "Ir para o fim", style: .chat) {}
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Metrics.floatingMargin)
                        .padding(.bottom, 8)
                }
                CollapsedComposer(draft: "")
                    .padding(.horizontal, Metrics.floatingMargin)
                    .padding(.bottom, Metrics.composerBottomInset)
            }
        }
    }
}

private struct PreviewChatColumn<Content: View>: View {
    var topInset: CGFloat?
    var bottomInset: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if topInset == nil {
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Metrics.listItemSpacing) {
                content()
            }
            .padding(.horizontal, Metrics.contentMargin)
            .padding(.top, topInset ?? 0)
            .padding(.bottom, bottomInset ?? 0)
            if bottomInset == nil {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewTools<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 6) {
            content()
        }
    }
}

private struct PreviewParagraph: View {
    let text: Text

    var body: some View {
        text
            .chatBodyStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreviewItalic: View {
    let text: Text

    var body: some View {
        text
            .chatText(.italic)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreviewThinking: View {
    let text: String

    var body: some View {
        Text(text)
            .chatText(.italic)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

private struct PreviewNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.mono(12, relativeTo: .caption))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity)
    }
}

private struct PreviewTile<Content: View>: View {
    let background: Color
    let size: CGFloat
    let radius: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay { content() }
    }
}

private struct PreviewUsageRow: View {
    let label: String
    let fraction: Double
    let pace: Double
    let remaining: String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(Typography.usageLabel)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 38.7, alignment: .trailing)
            UsageBar(fraction: fraction, paceFraction: pace)
                .frame(width: 153.7)
                .padding(.leading, 13.3)
            Text("\(Int(fraction * 100))%")
                .font(Typography.usageValue)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 47.3, alignment: .trailing)
            Text(remaining)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

private struct PreviewAccountRow: View {
    let label: String
    let fraction: Double
    let remaining: String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(Typography.usageLabel)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 63.7, alignment: .leading)
            UsageBar(fraction: fraction)
                .frame(width: 141.7)
            Text("\(Int(fraction * 100))%")
                .font(Typography.usageValue)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 48.3, alignment: .trailing)
            Text(remaining)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 24)
    }
}

private struct PreviewSheetLabel: View {
    let text: String
    var detail: String?

    var body: some View {
        Text("\(text.uppercased())\(detail.map { " " + $0 } ?? "")")
            .systemText(.sectionHeader)
            .systemLinePitch(16, size: 12)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 7)
    }
}

private struct PreviewHomeButtons: View {
    var body: some View {
        HStack {
            GlassRoundButton(icon: .sidebar, accessibilityLabel: "Abrir gaveta", style: .home) {}
            Spacer()
            GlassRoundButton(systemImage: "gearshape", accessibilityLabel: "Ajustes", style: .home) {}
        }
        .padding(.horizontal, Metrics.homeButtonSide)
        .padding(.top, Metrics.homeButtonTopInset)
    }
}

private enum PreviewText {
    static let loginSubtitle = "login-social • opus-5-5 • feat/login-social"
    static let testOutput = """
    Test Suite 'AppleSignInTests' started
    ✔ signInReturnsCredential() (0.012s)
    ✔ signInCancelledThrows() (0.004s)
    ✔ tokenIsSavedInKeychain() (0.021s)
    ✔ expiredTokenSignsOut() (0.009s)
    ✔ 6 tests passed in 0.071s

    [exited with code 0]
    """

    static func code(_ text: String) -> Text {
        Text(text).foregroundStyle(Palette.link)
    }
}
#endif
