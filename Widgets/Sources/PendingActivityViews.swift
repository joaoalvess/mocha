import AppIntents
import MochaClient
import SwiftUI

struct PendingActivityControls: View {
    let pending: AgentsActivityContent.Pending
    let agentId: String
    let metrics: AgentsCardMetrics

    var body: some View {
        let actions = AgentsActivityActions.actions(for: pending, agentId: agentId)
        if actions.isEmpty {
            questionHint
        } else {
            buttonRows(actions)
        }
    }

    private var questionHint: some View {
        HStack(spacing: 4) {
            Text(AgentsActivityText.questionHint)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: metrics.footnoteSize))
        .foregroundStyle(AgentsPalette.textSecondary)
    }

    private func buttonRows(_ actions: [AgentsActivityAction]) -> some View {
        let rows = rows(of: actions)
        let height = rows.count > 1 ? metrics.gridButtonHeight : metrics.buttonHeight
        return VStack(spacing: metrics.gridSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: rows.count > 1 ? 6 : 8) {
                    ForEach(rows[index].indices, id: \.self) { column in
                        PendingActionButton(action: rows[index][column], height: height)
                    }
                }
            }
        }
    }

    private func rows(of actions: [AgentsActivityAction]) -> [[AgentsActivityAction]] {
        let limit = AgentsActivityText.singleRowActionLimit
        guard actions.count > limit else { return [actions] }
        return stride(from: 0, to: actions.count, by: limit).map { Array(actions[$0..<min($0 + limit, actions.count)]) }
    }
}

struct PendingActionButton: View {
    let action: AgentsActivityAction
    let height: CGFloat

    var body: some View {
        switch action.choice {
        case .allow:
            Button(intent: AllowPendingRequestIntent(requestId: action.requestId, agentId: action.agentId)) { label }
                .buttonStyle(.plain)
        case .deny:
            Button(intent: DenyPendingRequestIntent(requestId: action.requestId, agentId: action.agentId)) { label }
                .buttonStyle(.plain)
        case .answer(let question, let option):
            Button(intent: AnswerPendingQuestionIntent(requestId: action.requestId, agentId: action.agentId, question: question, label: option)) { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        Text(action.title)
            .font(.system(size: action.role == .option ? 14 : 15, weight: action.role == .option ? .medium : .semibold))
            .foregroundStyle(action.role == .allow ? AgentsPalette.onStatusOk : AgentsPalette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(action.role == .allow ? AgentsPalette.statusOk : AgentsPalette.controlBg, in: Capsule())
            .contentShape(Capsule())
    }
}
