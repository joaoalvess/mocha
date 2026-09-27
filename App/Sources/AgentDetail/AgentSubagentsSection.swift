import MochaClient
import MochaProtocol
import SwiftUI

struct AgentSubagentsSection: View {
    let items: [SubagentSummary]
    let sessionId: String
    let onOpen: (ChatTarget) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if SubagentRows.hasRunning(items) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    card(now: context.date)
                }
            } else {
                card(now: Date())
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("SUBAGENTES")
            Spacer(minLength: 0)
            if let running = SubagentRows.runningCount(items) {
                Text(running.uppercased())
            }
        }
        .systemText(.sectionHeader)
        .foregroundStyle(Palette.textSecondary)
        .frame(height: 16)
        .padding(.horizontal, 16.3)
        .padding(.top, 20.3)
        .padding(.bottom, 7)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func card(now: Date) -> some View {
        let rows = SubagentRows.make(items: items, sessionId: sessionId, now: now)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.divider)
                        .frame(height: 1)
                }
                SubagentListRow(row: row)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(row.target) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Abre o transcript do subagente")
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.toolCard))
    }
}

private struct SubagentListRow: View {
    let row: SubagentRow

    var body: some View {
        HStack(spacing: 12) {
            SubagentStateIcon(status: row.status, size: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 20)
                subtitle
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 17)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.3, color: Palette.textSecondary)
        }
        .padding(.leading, row.isNested ? 44.3 : 16.3)
        .padding(.trailing, 16.7)
        .frame(height: 56)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: Text {
        guard row.status == .failed, let prefix = row.statusPrefix else {
            return Text(row.subtitle)
        }
        return Text("\(row.agentType) · \(Text(prefix).foregroundStyle(Palette.error)) · \(row.stats)")
    }
}
