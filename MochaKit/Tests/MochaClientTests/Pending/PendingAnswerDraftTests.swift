import Foundation
import MochaProtocol
import Testing
@testable import MochaClient

struct PendingAnswerDraftTests {
    @Test func singleSelectKeepsOnlyTheLastOption() {
        var draft = PendingQuestionDraft(question: PendingFixtures.formatQuestion)
        #expect(draft.answer == nil)
        draft.toggle("RSS 2.0")
        draft.toggle("Atom")
        #expect(draft.isSelected("Atom"))
        #expect(!draft.isSelected("RSS 2.0"))
        #expect(draft.answer == ["Atom"])
        draft.toggle("Atom")
        #expect(draft.answer == ["Atom"])
    }

    @Test func singleSelectOtherTextReplacesTheOptionAndBackAgain() {
        var draft = PendingQuestionDraft(question: PendingFixtures.formatQuestion)
        draft.toggle("Atom")
        draft.setOtherText("  JSON Feed \n")
        #expect(!draft.isSelected("Atom"))
        #expect(draft.isOtherChosen)
        #expect(draft.answer == ["JSON Feed"])
        draft.toggle("Os dois")
        #expect(!draft.isOtherChosen)
        #expect(draft.otherText == "  JSON Feed \n")
        #expect(draft.answer == ["Os dois"])
        draft.setOtherText("   ")
        #expect(draft.answer == ["Os dois"])
    }

    @Test func otherTextEqualToALabelBecomesThatLabel() {
        var draft = PendingQuestionDraft(question: PendingFixtures.formatQuestion)
        draft.setOtherText(" atom ")
        #expect(draft.answer == ["Atom"])
        #expect(PendingAnswerMatching.value(for: "rss 2.0", labels: ["RSS 2.0"]) == "RSS 2.0")
        #expect(PendingAnswerMatching.value(for: "sepia", labels: ["Sépia"]) == "Sépia")
        #expect(PendingAnswerMatching.value(for: " Outra coisa ", labels: ["Sépia"]) == "Outra coisa")
        #expect(PendingAnswerMatching.value(for: " \n", labels: ["Sépia"]).isEmpty)
    }

    @Test func multiSelectFollowsTheOptionOrderAndAppendsFreeText() {
        var draft = PendingQuestionDraft(question: PendingFixtures.testsQuestion)
        draft.toggle("UI")
        draft.toggle("Unitários")
        draft.setOtherText("Snapshot")
        #expect(draft.answer == ["Unitários", "UI", "Snapshot"])
        draft.toggle("UI")
        #expect(draft.answer == ["Unitários", "Snapshot"])
        draft.setOtherText("unitários")
        #expect(draft.answer == ["Unitários"])
        draft.toggle("Unitários")
        draft.setOtherText("")
        #expect(draft.answer == nil)
    }

    @Test func unknownLabelsAreIgnored() {
        var draft = PendingQuestionDraft(question: PendingFixtures.testsQuestion)
        draft.toggle("E2E")
        #expect(draft.selectedLabels.isEmpty)
    }

    @Test func responseNeedsEveryQuestionAnswered() throws {
        var draft = PendingAnswerDraft(questions: [PendingFixtures.formatQuestion, PendingFixtures.testsQuestion])
        #expect(!draft.isComplete)
        draft.toggle("Atom", inQuestion: 0)
        #expect(!draft.isComplete)
        #expect(draft.response == nil)
        draft.toggle("UI", inQuestion: 1)
        draft.setOtherText("Carga", inQuestion: 1)
        #expect(draft.isComplete)
        #expect(try #require(draft.response) == .answers([
            "Qual formato de feed você quer publicar?": ["Atom"],
            "Quais testes?": ["UI", "Carga"],
        ]))
    }

    @Test func outOfRangeQuestionsAreIgnored() {
        var draft = PendingAnswerDraft(questions: [PendingFixtures.formatQuestion])
        draft.toggle("Atom", inQuestion: 3)
        draft.setOtherText("x", inQuestion: -1)
        #expect(!draft.isComplete)
    }

    @Test func aDraftWithoutQuestionsIsNeverComplete() {
        #expect(!PendingAnswerDraft(questions: []).isComplete)
        #expect(PendingAnswerDraft(questions: []).response == nil)
    }

    @Test func repeatedQuestionTextKeepsTheFirstAnswer() throws {
        var draft = PendingAnswerDraft(questions: [PendingFixtures.formatQuestion, PendingFixtures.formatQuestion])
        draft.toggle("Atom", inQuestion: 0)
        draft.toggle("Os dois", inQuestion: 1)
        #expect(try #require(draft.response) == .answers(["Qual formato de feed você quer publicar?": ["Atom"]]))
    }
}
