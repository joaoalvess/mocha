import SwiftUI

struct BrowserScreen: View {
    @State var model: BrowserModel
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 8) {
            BrowserBar(title: model.title, onClose: close, onReload: model.reload)
                .padding(.horizontal, Metrics.contentMargin)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.black.ignoresSafeArea())
        .task { model.open() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.suspend()
            case .active:
                model.resume()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .connecting:
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Palette.textSecondary)
                Text(BrowserModel.connectingText)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
            }
        case .ready(let url):
            BrowserWebView(
                url: url,
                reloadCount: model.reloadCount,
                onTitle: model.titleChanged,
                onFailure: model.pageFailed
            )
            .ignoresSafeArea(.container, edges: .bottom)
        case .failed(let message, let pointsToSettings):
            BrowserFailureView(
                message: message,
                pointsToSettings: pointsToSettings,
                onRetry: model.retry,
                onOpenSettings: openSettings
            )
        }
    }

    private func close() {
        model.close()
        onClose()
    }

    private func openSettings() {
        close()
        onOpenSettings()
    }
}

private struct BrowserBar: View {
    let title: String
    let onClose: () -> Void
    let onReload: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            barButton(systemImage: "xmark", label: "Fechar", action: onClose)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            barButton(systemImage: "arrow.clockwise", label: "Recarregar", action: onReload)
        }
        .padding(.horizontal, 6)
        .frame(height: Metrics.headerHeight)
        .mochaGlass(.chat, in: Capsule())
    }

    private func barButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct BrowserFailureView: View {
    let message: String
    let pointsToSettings: Bool
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                if pointsToSettings {
                    actionButton("Abrir Ajustes", prominent: true, action: onOpenSettings)
                }
                actionButton("Tentar de novo", prominent: !pointsToSettings, action: onRetry)
            }
        }
        .padding(.horizontal, 32)
    }

    private func actionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(prominent ? Palette.black : Palette.textPrimary)
                .frame(minWidth: 180, minHeight: 44)
                .padding(.horizontal, 16)
                .background(prominent ? Palette.textPrimary : Color.clear, in: Capsule())
                .overlay {
                    if !prominent {
                        Capsule().stroke(Palette.textSecondary.opacity(0.5), lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}
