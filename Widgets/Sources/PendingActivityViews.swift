import AppIntents
import MochaClient
import SwiftUI

struct PendingActivityLayout {
    let headlineSize: CGFloat
    let detailSize: CGFloat
    let detailLines: Int
    let questionLines: Int
    let buttonHeight: CGFloat
    let gridButtonHeight: CGFloat
    let spacing: CGFloat

    static let lockScreen = PendingActivityLayout(
        headlineSize: 15,
        detailSize: 13,
        detailLines: 2,
        questionLines: 2,
        buttonHeight: 36,
        gridButtonHeight: 30,
        spacing: 10
    )

    static let island = PendingActivityLayout(
        headlineSize: 14,
        detailSize: 12,
        detailLines: 1,
        questionLines: 1,
        buttonHeight: 32,
        gridButtonHeight: 28,
        spacing: 8
    )
}

struct PendingActivitySection: View {
    let pending: AgentsActivityContent.Pending
    let workspaceLabel: String?
    let layout: PendingActivityLayout

    private var actions: [AgentsActivityAction] {
        AgentsActivityActions.actions(for: pending)
    }

    var body: some View {
        switch pending.kind {
        case .permission:
            permission
        case .question where !actions.isEmpty:
            question
        case .question:
            questionPreview
        }
    }

    private var permission: some View {
        let headline = AgentsActivityText.permissionHeadline(toolName: pending.toolName)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Text(headline.toolName).fontWeight(.semibold).foregroundStyle(AgentsPalette.textPrimary)) \(Text(headline.verb).foregroundStyle(AgentsPalette.textSecondary))")
                    .font(.system(size: layout.headlineSize))
                    .lineLimit(1)
                Spacer(minLength: 8)
                workspace
            }
            if !pending.text.isEmpty {
                detail(showsPrompt: headline.showsPrompt)
            }
            buttonRows
                .padding(.top, layout.spacing - 3)
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: layout.spacing) {
            Text(pending.text)
                .font(.system(size: layout.headlineSize - 1, weight: .semibold))
                .foregroundStyle(AgentsPalette.textPrimary)
                .lineLimit(layout.questionLines)
                .fixedSize(horizontal: false, vertical: true)
            buttonRows
        }
    }

    private var questionPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(PendingText.questionHeader)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AgentsPalette.waiting)
                Spacer(minLength: 8)
                workspace
            }
            Text(pending.text)
                .font(.system(size: layout.headlineSize - 1))
                .foregroundStyle(AgentsPalette.textPrimary)
                .lineLimit(layout.questionLines)
            HStack(spacing: 4) {
                Text(AgentsActivityText.questionHint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12))
            .foregroundStyle(AgentsPalette.textSecondary)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if let workspaceLabel, !workspaceLabel.isEmpty {
            Text(workspaceLabel)
                .font(.system(size: 12))
                .foregroundStyle(AgentsPalette.textSecondary)
                .lineLimit(1)
        }
    }

    private func detail(showsPrompt: Bool) -> some View {
        Group {
            if showsPrompt {
                Text("\(Text("$ ").foregroundStyle(AgentsPalette.link))\(pending.text)")
            } else {
                Text(pending.text)
            }
        }
        .font(.system(size: layout.detailSize, design: .monospaced))
        .foregroundStyle(AgentsPalette.textPrimary)
        .lineLimit(layout.detailLines)
    }

    private var buttonRows: some View {
        let rows = rows(of: actions)
        let height = rows.count > 1 ? layout.gridButtonHeight : layout.buttonHeight
        return VStack(spacing: 6) {
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
        guard actions.count > 2 else { return [actions] }
        return stride(from: 0, to: actions.count, by: 2).map { Array(actions[$0..<min($0 + 2, actions.count)]) }
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
