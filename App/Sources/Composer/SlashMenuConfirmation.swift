import MochaClient
import MochaProtocol
import SwiftUI

enum ClearConfirmationStyle {
    static let scrim = Color(hex: 0x000000, opacity: 0.5)
    static let background = Color(hex: 0x2C2C2E, opacity: 0.9)
    static let border = Color(hex: 0xFFFFFF, opacity: 0.12)
    static let button = Color(hex: 0xFFFFFF, opacity: 0.1)
    static let message = Color(hex: 0xC5C8CD)
    static let cornerRadius: CGFloat = 32
    static let sideInset: CGFloat = 45
    static let verticalOffset: CGFloat = -28
    static let buttonHeight: CGFloat = 46
}

struct ClearConfirmation: View {
    var provider: AgentProvider = .claude
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var messageSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 16

    var body: some View {
        ZStack {
            ClearConfirmationStyle.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            card
                .padding(.horizontal, ClearConfirmationStyle.sideInset)
                .offset(y: ClearConfirmationStyle.verticalOffset)
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("Limpar a conversa?")
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .systemLinePitch(22, size: titleSize)
                .accessibilityAddTraits(.isHeader)
            Text("O \(PendingText.agentName(for: provider)) começa uma sessão nova nesta tab do Herdr. O histórico atual continua salvo no Mac.")
                .font(.system(size: messageSize))
                .foregroundStyle(ClearConfirmationStyle.message)
                .multilineTextAlignment(.center)
                .systemLinePitch(19, size: messageSize)
                .padding(.top, 6)
            HStack(spacing: 10) {
                button("Cancelar", color: Palette.textPrimary, action: onCancel)
                button("Limpar", color: Palette.destructive, action: onConfirm)
            }
            .padding(.top, 18)
        }
        .padding(.top, 22)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(ClearConfirmationStyle.background))
        .overlay(cardShape.strokeBorder(ClearConfirmationStyle.border, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 22)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onCancel)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ClearConfirmationStyle.cornerRadius, style: .continuous)
    }

    private func button(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: buttonSize, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: ClearConfirmationStyle.buttonHeight)
                .background(Capsule().fill(ClearConfirmationStyle.button))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}
