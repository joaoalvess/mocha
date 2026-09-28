import Foundation
import MochaProtocol

public struct PendingQuestionDraft: Sendable, Equatable {
    public let question: PendingQuestion
    public private(set) var selectedLabels: Set<String> = []
    public private(set) var otherText = ""
    public private(set) var isOtherChosen = false

    public init(question: PendingQuestion) {
        self.question = question
    }

    public func isSelected(_ label: String) -> Bool {
        selectedLabels.contains(label)
    }

    public mutating func toggle(_ label: String) {
        guard question.options.contains(where: { $0.label == label }) else { return }
        if question.multiSelect {
            if selectedLabels.contains(label) {
                selectedLabels.remove(label)
            } else {
                selectedLabels.insert(label)
            }
        } else {
            selectedLabels = [label]
            isOtherChosen = false
        }
    }

    public mutating func setOtherText(_ text: String) {
        otherText = text
        let hasText = !PendingAnswerMatching.trimmed(text).isEmpty
        if question.multiSelect {
            isOtherChosen = hasText
        } else if hasText {
            isOtherChosen = true
            selectedLabels = []
        } else {
            isOtherChosen = false
        }
    }

    public var answer: [String]? {
        let labels = question.options.map(\.label).filter { selectedLabels.contains($0) }
        var values: [String] = []
        for label in labels where !values.contains(label) {
            values.append(label)
        }
        if isOtherChosen {
            let typed = PendingAnswerMatching.value(for: otherText, labels: question.options.map(\.label))
            if !typed.isEmpty, !values.contains(typed) {
                values.append(typed)
            }
        }
        return values.isEmpty ? nil : values
    }
}

public struct PendingAnswerDraft: Sendable, Equatable {
    public private(set) var questions: [PendingQuestionDraft]
    public private(set) var step = 0

    public init(questions: [PendingQuestion]) {
        self.questions = questions.map(PendingQuestionDraft.init(question:))
    }

    public var isStepped: Bool {
        questions.count > 1
    }

    public var isLastStep: Bool {
        step >= questions.count - 1
    }

    public var isCurrentStepAnswered: Bool {
        questions.indices.contains(step) && questions[step].answer != nil
    }

    public mutating func advance() {
        guard !isLastStep, isCurrentStepAnswered else { return }
        step += 1
    }

    public mutating func goBack() {
        guard step > 0 else { return }
        step -= 1
    }

    public mutating func choose(_ label: String) {
        toggle(label, inQuestion: step)
        guard isStepped, questions.indices.contains(step), !questions[step].question.multiSelect else { return }
        advance()
    }

    public var isComplete: Bool {
        !questions.isEmpty && questions.allSatisfy { $0.answer != nil }
    }

    public var response: PendingResponse? {
        guard isComplete else { return nil }
        var answers: [String: [String]] = [:]
        for draft in questions where answers[draft.question.question] == nil {
            answers[draft.question.question] = draft.answer
        }
        return .answers(answers)
    }

    public mutating func toggle(_ label: String, inQuestion index: Int) {
        guard questions.indices.contains(index) else { return }
        questions[index].toggle(label)
    }

    public mutating func setOtherText(_ text: String, inQuestion index: Int) {
        guard questions.indices.contains(index) else { return }
        questions[index].setOtherText(text)
    }
}

public enum PendingAnswerMatching {
    public static func value(for text: String, labels: [String]) -> String {
        let typed = trimmed(text)
        guard !typed.isEmpty else { return "" }
        if let label = labels.first(where: { $0 == typed }) {
            return label
        }
        return labels.first { trimmed($0).compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } ?? typed
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
