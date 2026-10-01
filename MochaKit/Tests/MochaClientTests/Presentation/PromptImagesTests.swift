import Testing
@testable import MochaClient

struct PromptImagesTests {
    private static let uploads = "/Users/joao/Library/Application Support/Mocha/uploads"

    @Test func promptPutsTheTextFirstAndOnePathLinePerImageInOrder() {
        let text = PromptImages.promptText(
            "o que tem de errado\nnessa tela?",
            imagePaths: ["\(Self.uploads)/a.jpg", "\(Self.uploads)/b.jpg", "\(Self.uploads)/c.jpg"]
        )
        #expect(text == """
        o que tem de errado
        nessa tela?
        \(Self.uploads)/a.jpg
        \(Self.uploads)/b.jpg
        \(Self.uploads)/c.jpg
        """)
    }

    @Test func promptWithoutTextIsOnlyThePaths() {
        let text = PromptImages.promptText("", imagePaths: ["\(Self.uploads)/a.jpg", "\(Self.uploads)/b.jpg"])
        #expect(text == "\(Self.uploads)/a.jpg\n\(Self.uploads)/b.jpg")
    }

    @Test func promptWithoutImagesIsTheTextUnchanged() {
        #expect(PromptImages.promptText("roda os testes", imagePaths: []) == "roda os testes")
    }

    @Test func attachmentLabelUsesSingularAndPlural() {
        #expect(PromptImages.attachmentLabel(imageCount: 1) == "📎 1 imagem")
        #expect(PromptImages.attachmentLabel(imageCount: 2) == "📎 2 imagens")
        #expect(PromptImages.attachmentLabel(imageCount: 5) == "📎 5 imagens")
    }

    @Test func bubbleTextAddsTheAttachmentLineBelowTheText() {
        #expect(PromptImages.bubbleText("olha isso", imageCount: 2) == "olha isso\n📎 2 imagens")
        #expect(PromptImages.bubbleText("", imageCount: 1) == "📎 1 imagem")
        #expect(PromptImages.bubbleText(" \n", imageCount: 3) == "📎 3 imagens")
        #expect(PromptImages.bubbleText("sem imagem", imageCount: 0) == "sem imagem")
    }

    @Test func attachmentLineCountsOnlyTheImagesWithoutAFile() {
        let paths = ["\(Self.uploads)/a.jpg", "\(Self.uploads)/b.jpg"]
        #expect(PromptImages.bubbleText("olha isso", imageCount: 3, imagePaths: paths) == "olha isso\n📎 1 imagem")
        #expect(PromptImages.bubbleText("", imageCount: 4, imagePaths: paths) == "📎 2 imagens")
        #expect(PromptImages.bubbleText("olha isso", imageCount: 2, imagePaths: paths) == "olha isso")
        #expect(PromptImages.bubbleText("", imageCount: 2, imagePaths: paths).isEmpty)
        #expect(PromptImages.missingImageCount(imageCount: 1, imagePaths: paths) == 0)
        #expect(PromptImages.missingImageCount(imageCount: 5, imagePaths: paths) == 3)
    }
}
