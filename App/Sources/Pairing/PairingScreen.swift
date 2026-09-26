import MochaClient
import MochaProtocol
import SwiftUI
import UIKit

struct PairingScreen: View {
    @Bindable var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var isScanning = false
    @State private var clipboardHasContent = false
    @State private var rejectedPaste = false

    private static let leadEmphasis = Color(hex: 0xD9DBDF)

    var body: some View {
        ZStack(alignment: .top) {
            HomeBackground()
            ScrollView {
                VStack(spacing: 0) {
                    PairingLogo()
                        .padding(.top, 101)
                    Text("Parear com o Mac")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .systemLinePitch(32, size: 26)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.top, 26)
                    lead
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                    PairingSteps()
                        .padding(.top, notice == nil ? 32 : 22)
                    noticeView
                    readQRButton
                        .padding(.top, notice == nil ? 68 : 23)
                    linkField
                        .padding(.top, 12)
                }
                .padding(.horizontal, Metrics.contentMargin)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .fullScreenCover(isPresented: $isScanning) {
            QRScannerScreen { link in
                pair(link)
            } onClose: {
                isScanning = false
            }
        }
        .onChange(of: session.pairing.connectingHost) { old, new in
            if old != nil, new == nil {
                isScanning = false
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                refreshClipboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            refreshClipboard()
        }
    }

    private var lead: some View {
        Text("O Mocha conversa com o \(Text("mochad").fontWeight(.medium).foregroundStyle(Self.leadEmphasis)) no seu Mac pelo Tailscale.")
            .font(.system(size: 15))
            .systemLinePitch(21, size: 15)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notice: PairingNotice? {
        if let host = session.pairing.connectingHost {
            return .connecting(host: host)
        }
        if rejectedPaste {
            return .invalidLink
        }
        return session.pairing.problem.map(PairingNotice.problem)
    }

    @ViewBuilder
    private var noticeView: some View {
        switch notice {
        case .connecting(let host)?:
            PairingProgressPill(text: "Conectando ao \(host)…")
                .padding(.top, 18)
        case .problem(let problem)?:
            PairingErrorCard(message: problem.message, detail: problem == .pairingExpired ? "Os códigos valem 10 minutos." : nil)
                .padding(.top, 18)
        case .invalidLink?:
            PairingErrorCard(message: "O link copiado não é um link de pareamento do `mochad`", detail: nil)
                .padding(.top, 18)
        case nil:
            EmptyView()
        }
    }

    private var readQRButton: some View {
        Button {
            rejectedPaste = false
            isScanning = true
        } label: {
            HStack(spacing: 10) {
                PairingGlyphView(glyph: .qr, size: 21, strokeWidth: 2, color: Palette.ctaText)
                Text("Ler QR")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ctaText)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Palette.textPrimary))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private var linkField: some View {
        HStack(spacing: 10) {
            PairingGlyphView(glyph: .link, size: 17, strokeWidth: 2, color: Palette.textSecondary)
            Text("mocha://pair?url=…")
                .monoText(13, relativeTo: .footnote)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if clipboardHasContent {
                Button(action: pasteLink) {
                    Text("Colar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(Palette.controlBg))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Capsule().fill(Palette.toolCard))
    }

    private func refreshClipboard() {
        clipboardHasContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
    }

    private func pasteLink() {
        let text = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let link = PairingLink(url) else {
            rejectedPaste = true
            return
        }
        pair(link)
    }

    private func pair(_ link: PairingLink) {
        rejectedPaste = false
        session.pair(link)
    }
}

private enum PairingNotice: Equatable {
    case connecting(host: String)
    case problem(ConnectionProblem)
    case invalidLink
}

private struct PairingLogo: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Palette.pairingLogoTop, Palette.pairingLogoBottom], startPoint: UnitPoint(x: 0.37, y: 0), endPoint: UnitPoint(x: 0.63, y: 1)))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.textPrimary.opacity(0.1), lineWidth: 0.7)
            }
            .overlay {
                PairingGlyphView(glyph: .cup, size: 54, strokeWidth: 1.9, color: Palette.claude)
            }
            .frame(width: 88, height: 88)
            .shadow(color: Palette.glyphOnAccent.opacity(0.5), radius: 20, y: 16)
            .accessibilityHidden(true)
    }
}

private struct PairingSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PairingStepRow(number: 1, text: Text("No Mac, rode \(PairingCode.text("mochad pair")) no terminal."))
            PairingStepRow(number: 2, text: Text("Toque em \(Text("Ler QR").fontWeight(.semibold)) e aponte para o código."))
            PairingStepRow(number: 3, text: Text("O código vale 10 minutos e serve uma vez só."))
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.toolCard))
    }
}

private struct PairingStepRow: View {
    let number: Int
    let text: Text

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.controlBg))
                .padding(.top, -0.5)
            text
                .font(.system(size: 15))
                .systemLinePitch(21, size: 15)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

enum PairingCode {
    static func text(_ code: String, size: CGFloat = 14, color: Color = Palette.link) -> Text {
        Text(code)
            .font(Typography.mono(size, relativeTo: .subheadline))
            .foregroundStyle(color)
    }

    static func message(_ message: String, size: CGFloat = 14, color: Color = Palette.link) -> Text {
        message.split(separator: "`", omittingEmptySubsequences: false)
            .enumerated()
            .reduce(Text(verbatim: "")) { partial, segment in
                let piece = segment.offset.isMultiple(of: 2) ? Text(verbatim: String(segment.element)) : text(String(segment.element), size: size, color: color)
                return Text("\(partial)\(piece)")
            }
    }
}

private struct PairingErrorCard: View {
    let message: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PairingGlyphView(glyph: .warning, size: 20, strokeWidth: 2, color: Palette.destructive)
                .padding(.top, 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(PairingCode.message(message)).")
                    .font(.system(size: 15))
                    .systemLinePitch(21, size: 15)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .systemLinePitch(18, size: 13)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.error.opacity(0.11))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.error.opacity(0.38), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PairingProgressPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            PairingSpinner()
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .mochaGlass(.black, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct PairingSpinner: View {
    @State private var isRotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.textPrimary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Palette.textPrimary, lineWidth: 2)
                .rotationEffect(.degrees(isRotating ? 225 : -135))
        }
        .frame(width: 12, height: 12)
        .padding(1)
        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isRotating)
        .onAppear { isRotating = true }
        .accessibilityHidden(true)
    }
}
