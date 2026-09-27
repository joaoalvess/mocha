import MochaProtocol
import MochaTranscript

extension LiveActivityContentState.Pending {
    static let inlineQuestionByteLimit = 1_000
    static let inlineOptionRange = 1...4
    static let inlineLabelLimit = 60
    static let encodedByteBudget = 3_200

    var fitsEncodedBudget: Bool {
        ((try? ApnsPayloadEncoding.encoder.encode(self))?.count ?? .max) <= Self.encodedByteBudget
    }

    init(_ request: PendingRequest) {
        switch request.kind {
        case .permission(let toolName, let summary, _):
            self.init(
                requestId: request.id,
                agentId: request.agentId,
                kind: .permission,
                toolName: toolName,
                text: String(summary.prefix(PushAlertText.summaryLimit)),
                options: []
            )
        case .question(let questions):
            let preview = Self(
                requestId: request.id,
                agentId: request.agentId,
                kind: .question,
                toolName: nil,
                text: PlainText.preview(fromMarkdown: questions.first?.question ?? "", limit: PushAlertText.bodyLimit),
                options: []
            )
            guard let inline = Self.inlineQuestion(in: questions) else {
                self = preview
                return
            }
            let answerable = Self(
                requestId: request.id,
                agentId: request.agentId,
                kind: .question,
                toolName: nil,
                text: inline.question,
                options: inline.options.map(\.label)
            )
            self = answerable.fitsEncodedBudget ? answerable : preview
        }
    }

    static func inlineQuestion(in questions: [PendingQuestion]) -> PendingQuestion? {
        guard questions.count == 1, let question = questions.first, !question.multiSelect,
              question.question.utf8.count <= inlineQuestionByteLimit,
              inlineOptionRange.contains(question.options.count),
              question.options.allSatisfy({ $0.label.count <= inlineLabelLimit })
        else { return nil }
        return question
    }
}
