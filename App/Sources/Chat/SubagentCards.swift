import MochaClient
import MochaProtocol
import SwiftUI

struct SubagentCard: View {
    let call: SubagentCall
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                LineIconView(icon: .agent, size: 15, strokeWidth: 1.9, color: Palette.textSecondary)
                    .padding(.trailing, 6.6)
                Text("\(Text(call.agentType).font(Typography.toolCardName).foregroundStyle(Palette.textPrimary)) \(call.description)")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubagentStateIcon(status: call.status)
                    .padding(.leading, 10)
            }
            .frame(height: 16)
            if call.status == .running, let activity = call.activity {
                HStack(spacing: 0) {
                    SubagentCardIndent()
                    ToolIconView(icon: ToolPresentation.icon(for: activity.toolName), size: 13)
                        .padding(.trailing, 6)
                    Text("\(Text(ToolPresentation.displayName(for: activity.toolName)).foregroundStyle(Palette.textPrimary)) \(activity.summary)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.trailing, 25)
                .frame(height: 16)
            }
            HStack(spacing: 0) {
                SubagentCardIndent()
                SubagentStatsText(status: call.status, startedAt: call.startedAt, durationMs: call.durationMs, toolUses: call.toolUses)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.3, color: Palette.textSecondary)
                    .padding(.leading, 11.5)
                    .padding(.trailing, 1.5)
            }
            .frame(height: 16)
        }
        .font(Typography.toolCard)
        .foregroundStyle(Palette.textSecondary)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.leading, 12.7)
        .padding(.trailing, 15)
        .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(Palette.toolCard))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .circular))
        .onTapGesture {
            if let agentId = call.agentId { onOpen(agentId) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(call.agentId == nil ? [] : .isButton)
        .accessibilityHint(call.agentId == nil ? "" : "Abre o transcript do subagente")
    }
}

private struct SubagentCardIndent: View {
    var body: some View {
        Color.clear.frame(width: 21.6, height: 1)
    }
}

struct SubagentStatsText: View {
    let status: SubagentStatus
    let startedAt: Date?
    let durationMs: Int?
    let toolUses: Int

    var body: some View {
        if status == .running, let startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                line(now: context.date)
            }
        } else {
            line(now: Date())
        }
    }

    private func line(now: Date) -> some View {
        let stats = SubagentText.statsLine(
            elapsed: SubagentText.elapsed(status: status, startedAt: startedAt, durationMs: durationMs, now: now),
            toolUses: toolUses
        )
        let text: Text
        switch status {
        case .failed:
            text = Text("\(Text("falhou").foregroundStyle(Palette.error)) • \(stats)")
        case .stopped:
            text = Text("parado • \(stats)")
        case .running, .completed:
            text = Text(stats)
        }
        return text
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

struct TaskCard: View {
    let text: String
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                LineIconView(icon: .agent, size: 15, strokeWidth: 2, color: Palette.textSecondary)
                Text("Tarefa")
                    .font(Typography.toolCardName)
            }
            .frame(height: 18)
            .padding(.leading, 2)
            Text(text)
                .chatText()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(isExpanded ? nil : 4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
                .padding(.horizontal, 2)
            if !isExpanded {
                HStack(spacing: 4) {
                    LineIconView(icon: .chevronRight, size: 12, strokeWidth: 2.2, color: Palette.textSecondary)
                        .rotationEffect(.degrees(90))
                    Text("Ver tarefa completa")
                        .font(Typography.toolCard)
                }
                .frame(height: 16)
                .padding(.top, 8)
                .padding(.horizontal, 2)
            }
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(Palette.toolCard))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .circular))
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Recolhe a tarefa" : "Mostra a tarefa completa")
    }
}

struct WorkflowCard: View {
    let call: WorkflowCall
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                phases
                    .padding(.horizontal, 12)
                footer
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

    private var header: some View {
        HStack(spacing: 0) {
            LineIconView(icon: .flow, size: 15, strokeWidth: 1.9, color: Palette.textSecondary)
                .padding(.trailing, 6.6)
            Text("\(Text("Workflow").font(Typography.toolCardName).foregroundStyle(Palette.textPrimary)) \(headerSummary)")
                .font(Typography.toolCard)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            SubagentStateIcon(status: SubagentStatus(call.status))
                .padding(.leading, 10)
        }
        .padding(.leading, 12.7)
        .padding(.trailing, 15)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Recolhe as fases" : "Mostra as fases")
    }

    private var headerSummary: String {
        isExpanded ? call.name : SubagentText.workflowCollapsed(name: call.name, agentCount: call.agentCount)
    }

    private var phases: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(call.phases.enumerated()), id: \.offset) { _, phase in
                WorkflowPhaseRow(phase: phase)
                if phase.status == .running {
                    if let detail = phase.detail, !detail.isEmpty {
                        Text(detail)
                            .font(Typography.mono(Typography.toolCardSize, .italic, relativeTo: .caption))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: 18)
                            .padding(.leading, 22)
                    }
                    ForEach(phase.agents, id: \.agentId) { agent in
                        WorkflowAgentRow(agent: agent)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(agent.agentId) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Abre o transcript do agente")
                    }
                }
            }
        }
        .font(Typography.toolCard)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Palette.codeInner))
    }

    private var footer: some View {
        Group {
            if call.status == .running, let startedAt = call.startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    footerText(now: context.date)
                }
            } else {
                footerText(now: Date())
            }
        }
        .padding(.top, 9)
        .padding(.leading, 24)
        .padding(.trailing, 15)
        .padding(.bottom, 11)
    }

    private func footerText(now: Date) -> some View {
        Text(SubagentText.workflowFooter(elapsed: SubagentText.workflowElapsed(call, now: now), agentCount: call.agentCount, toolUses: call.toolUses))
            .font(Typography.toolCard)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 16)
    }
}

private struct WorkflowPhaseRow: View {
    let phase: WorkflowPhase

    var body: some View {
        HStack(spacing: 0) {
            icon
                .padding(.trailing, 9)
            Text(phase.title)
                .font(phase.status == .running ? Typography.toolCardName : Typography.toolCard)
                .foregroundStyle(phase.status == .running ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(SubagentText.phaseCount(phase))
                .lineLimit(1)
                .padding(.leading, 10)
        }
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch phase.status {
        case .completed:
            LineIconView(icon: .check, size: 13, strokeWidth: 2.2, color: Palette.textSecondary)
        case .running:
            ToolSpinner(diameter: 13)
        case .failed:
            LineIconView(icon: .xCircle, size: 13, strokeWidth: 1.8, color: Palette.error)
        case .pending:
            Circle()
                .strokeBorder(Palette.sepDot, lineWidth: 1.6)
                .frame(width: 11, height: 11)
                .padding(.leading, 1)
                .padding(.trailing, 1)
        }
    }
}

private struct WorkflowAgentRow: View {
    let agent: WorkflowAgent

    var body: some View {
        HStack(spacing: 0) {
            icon
                .frame(width: 11, height: 11)
                .padding(.trailing, 8)
            Text(agent.label)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64, alignment: .leading)
            summary
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 20)
        .padding(.leading, 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch agent.status {
        case .running:
            ToolSpinner(diameter: 11, lineWidth: 1.6)
        case .completed:
            LineIconView(icon: .check, size: 11, strokeWidth: 2.3, color: Palette.textSecondary)
        case .failed, .stopped:
            SubagentStateIcon(status: agent.status, size: 11)
        }
    }

    private var summary: Text {
        if agent.status == .running, let activity = agent.activity {
            return Text("\(Text(ToolPresentation.displayName(for: activity.toolName)).foregroundStyle(Palette.textPrimary)) \(activity.summary)")
        }
        return Text(agent.durationMs.map(SubagentText.duration(milliseconds:)) ?? "")
    }
}

extension SubagentStatus {
    init(_ status: WorkflowStatus) {
        switch status {
        case .running: self = .running
        case .completed: self = .completed
        case .failed: self = .failed
        case .stopped: self = .stopped
        }
    }
}
