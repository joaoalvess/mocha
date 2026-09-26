import MochaClient
import SwiftUI

struct WorkingStatusLine: View {
    let startedAt: Date?
    let canStop: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            WorkingAsterisk()
                .stroke(Palette.textPrimary, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 10)
                .padding(.leading, 1)
                .padding(.trailing, 8)
            Text("Trabalhando…")
                .foregroundStyle(Palette.textPrimary)
            if let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text("(\(TurnDuration.text(from: startedAt, to: context.date)))")
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.leading, 7)
                }
            }
            Spacer(minLength: 8)
            StopTurnButton(isEnabled: canStop, action: onStop)
        }
        .font(Typography.toolCard)
        .lineLimit(1)
        .frame(height: 20)
        .accessibilityElement(children: .contain)
    }
}

struct WorkingAsterisk: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 2.5))
        path.addLine(to: CGPoint(x: 12, y: 21.5))
        path.move(to: CGPoint(x: 3.8, y: 7.2))
        path.addLine(to: CGPoint(x: 20.2, y: 16.8))
        path.move(to: CGPoint(x: 3.8, y: 16.8))
        path.addLine(to: CGPoint(x: 20.2, y: 7.2))
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return path.applying(transform)
    }
}

struct StopTurnButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Palette.statusOk.opacity(0.18), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Palette.statusOk, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-60))
                    .spinning(period: 1.4)
                RoundedRectangle(cornerRadius: 1.6, style: .circular)
                    .fill(Palette.textPrimary)
                    .frame(width: 7, height: 7)
            }
            .frame(width: 17.8, height: 17.8)
            .frame(width: 20, height: 20)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .padding(-12)
        .disabled(!isEnabled)
        .accessibilityLabel("Parar o Claude")
    }
}

struct PendingBubbleRow: View {
    let bubble: PendingBubble
    let onDiscard: () -> Void
    @State private var now = Date()

    var body: some View {
        let isUnconfirmed = bubble.isUnconfirmed(at: now)
        UserBubble(text: bubble.displayText, delivery: isUnconfirmed ? .unconfirmed : .sending)
            .contentShape(Rectangle())
            .onTapGesture {
                if isUnconfirmed { onDiscard() }
            }
            .accessibilityHint(isUnconfirmed ? "Toque para descartar" : "")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .task(id: bubble.id) {
                let remaining = bubble.confirmationDeadline.timeIntervalSinceNow
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
                guard !Task.isCancelled else { return }
                now = Date()
            }
    }
}

struct OlderItemsLoader: View {
    var body: some View {
        ProgressView()
            .tint(Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .accessibilityLabel("Carregando mensagens anteriores")
    }
}
