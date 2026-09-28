import MochaProtocol
import Testing
@testable import MochaClient

struct PendingAnswerStepsTests {
    private static let pet = PendingQuestion(
        header: "Pet",
        question: "Cachorro ou gato?",
        options: [PendingOption(label: "Cachorro"), PendingOption(label: "Gato")],
        multiSelect: false
    )
    private static let snacks = PendingQuestion(
        header: "Lanche",
        question: "O que você come?",
        options: [PendingOption(label: "Pipoca"), PendingOption(label: "Chocolate")],
        multiSelect: true
    )
    private static let genre = PendingQuestion(
        header: "",
        question: "Qual gênero?",
        options: [PendingOption(label: "Comédia"), PendingOption(label: "Terror")],
        multiSelect: false
    )

    @Test func aSingleQuestionIsNotStepped() {
        var draft = PendingAnswerDraft(questions: [Self.pet])
        #expect(!draft.isStepped)
        draft.choose("Gato")
        #expect(draft.step == 0)
        #expect(draft.response == .answers(["Cachorro ou gato?": ["Gato"]]))
    }

    @Test func aSingleChoiceAdvancesAndMultiSelectWaitsForNext() {
        var draft = PendingAnswerDraft(questions: [Self.pet, Self.snacks, Self.genre])
        #expect(draft.isStepped)
        draft.advance()
        #expect(draft.step == 0)
        draft.choose("Gato")
        #expect(draft.step == 1)
        draft.choose("Pipoca")
        draft.choose("Chocolate")
        #expect(draft.step == 1)
        #expect(draft.isCurrentStepAnswered)
        draft.advance()
        #expect(draft.step == 2)
        #expect(draft.isLastStep)
        #expect(!draft.isComplete)
        draft.choose("Terror")
        #expect(draft.step == 2)
        #expect(draft.response == .answers([
            "Cachorro ou gato?": ["Gato"],
            "O que você come?": ["Pipoca", "Chocolate"],
            "Qual gênero?": ["Terror"],
        ]))
    }

    @Test func goingBackKeepsTheAnswers() {
        var draft = PendingAnswerDraft(questions: [Self.pet, Self.genre])
        draft.choose("Cachorro")
        draft.goBack()
        #expect(draft.step == 0)
        #expect(draft.questions[0].isSelected("Cachorro"))
        draft.goBack()
        #expect(draft.step == 0)
    }

    @Test func theOtherTextAnswersTheStepWithoutAdvancing() {
        var draft = PendingAnswerDraft(questions: [Self.pet, Self.genre])
        draft.setOtherText("Peixe", inQuestion: 0)
        #expect(draft.step == 0)
        #expect(draft.isCurrentStepAnswered)
        draft.advance()
        #expect(draft.step == 1)
    }

    @Test func theStepLabelNamesTheHeaderAndThePosition() {
        #expect(PendingText.questionStep(header: "Pet", step: 0, total: 3) == "Pet · 1 de 3")
        #expect(PendingText.questionStep(header: " ", step: 2, total: 3) == "3 de 3")
    }
}
