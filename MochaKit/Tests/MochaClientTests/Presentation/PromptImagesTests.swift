import Testing
@testable import MochaClient

struct PromptImagesTests {
    private static let uploads = "/Users/joao/Library/Application Support/Mocha/uploads"

    @Test func promptPutsTheTextFirstAndOneMarkerLinePerImageInOrder() {
        let text = PromptImages.promptText(
            "o que tem de errado\nnessa tela?",
            imagePaths: ["\(Self.uploads)/a.jpg", "\(Self.uploads)/b.jpg", "\(Self.uploads)/c.jpg"]
        )
        #expect(text == """
        o que tem de errado
        nessa tela?
        [imagem: \(Self.uploads)/a.jpg]
        [imagem: \(Self.uploads)/b.jpg]
        [imagem: \(Self.uploads)/c.jpg]
        """)
    }

    @Test func promptWithoutTextIsOnlyTheMarkers() {
        let text = PromptImages.promptText("", imagePaths: ["\(Self.uploads)/a.jpg", "\(Self.uploads)/b.jpg"])
        #expect(text == "[imagem: \(Self.uploads)/a.jpg]\n[imagem: \(Self.uploads)/b.jpg]")
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
}
