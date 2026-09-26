import MochaClient
import MochaProtocol
import SwiftUI

struct ToolCallCard<Details: View>: View {
    let icon: ToolIcon
    let name: String
    let count: Int
    let summary: String
    let status: ToolStatus
    let isExpanded: Bool
    @ViewBuilder let details: () -> Details

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolCallRow(icon: icon, name: name, count: count, summary: summary, status: status)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    details()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(shape.fill(Palette.toolCard))
        .overlay {
            if isExpanded {
                shape.strokeBorder(Palette.toolBorder, lineWidth: 1)
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .circular)
    }
}

extension ToolCallCard where Details == EmptyView {
    init(icon: ToolIcon, name: String, count: Int, summary: String, status: ToolStatus) {
        self.init(icon: icon, name: name, count: count, summary: summary, status: status, isExpanded: false) {
            EmptyView()
        }
    }
}

struct ToolCallRow: View {
    let icon: ToolIcon
    let name: String
    let count: Int
    let summary: String
    let status: ToolStatus

    var body: some View {
        HStack(spacing: 0) {
            ToolIconView(icon: icon)
                .padding(.trailing, 6.6)
            label
                .font(Typography.toolCard)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            ToolStatusIcon(status: status)
                .padding(.leading, 10)
        }
        .padding(.leading, 12.7)
        .padding(.trailing, 15)
        .frame(height: 32)
        .accessibilityElement(children: .combine)
    }

    private var label: Text {
        let nameText = Text(name).font(Typography.toolCardName).foregroundStyle(Palette.textPrimary)
        let summaryText = Text(summary).foregroundStyle(Palette.textSecondary)
        guard count > 1 else {
            return Text("\(nameText) \(summaryText)")
        }
        let countText = Text("×\(count)").foregroundStyle(Palette.textSecondary)
        return Text("\(nameText) \(countText) \(summaryText)")
    }
}

struct ToolCallDetailBox: View {
    let input: String
    var showsPrompt = true
    let output: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            commandText
                .foregroundStyle(Palette.textPrimary)
                .linePitch(18, size: Typography.toolCardSize)
                .fixedSize(horizontal: false, vertical: true)
            if let output, !output.isEmpty {
                Text(output)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(nil)
                    .linePitch(18, size: Typography.toolCardSize)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
        }
        .font(Typography.toolCard)
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Palette.codeInner))
    }

    @ViewBuilder
    private var commandText: some View {
        if showsPrompt {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("$ ").foregroundStyle(Palette.link)
                Text(input)
            }
        } else {
            Text(input)
        }
    }
}

struct ToolStatusIcon: View {
    let status: ToolStatus

    var body: some View {
        switch status {
        case .running:
            ToolSpinner()
                .accessibilityLabel("Rodando")
        case .succeeded:
            LineIconView(icon: .check, size: 15, strokeWidth: 2, color: Palette.textSecondary)
                .accessibilityElement()
                .accessibilityLabel("Concluída")
        case .failed:
            LineIconView(icon: .xCircle, size: 15, strokeWidth: 1.8, color: Palette.error)
                .accessibilityElement()
                .accessibilityLabel("Falhou")
        }
    }
}

struct ToolSpinner: View {
    var diameter: CGFloat = 13
    var lineWidth: CGFloat = 1.8
    var color: Color = Palette.textSecondary

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90 - 45))
                .spinning(period: 0.9)
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
    }
}

extension View {
    func spinning(period: Double) -> some View {
        modifier(SpinningModifier(period: period))
    }
}

private struct SpinningModifier: ViewModifier {
    let period: Double

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let fraction = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            content.rotationEffect(.degrees(fraction * 360))
        }
    }
}
