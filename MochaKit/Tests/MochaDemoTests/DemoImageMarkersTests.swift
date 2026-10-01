import MochaProtocol
import Testing
@testable import MochaDemo

@Suite struct DemoImageMarkersTests {
    private let uploads = "/Users/demo/Library/Application Support/Mocha/uploads"

    @Test func markersLeaveTheTextAndCountAsImages() {
        let text = "olha esses prints\n[imagem: \(uploads)/a.jpg]\n[imagem: \(uploads)/b.jpg]"
        let prompt = DemoImageMarkers.split(text)
        #expect(prompt.text == "olha esses prints")
        #expect(prompt.imageCount == 2)
        #expect(prompt.imagePaths == ["\(uploads)/a.jpg", "\(uploads)/b.jpg"])
    }

    @Test func promptWithOnlyMarkersBecomesEmpty() {
        let prompt = DemoImageMarkers.split("[imagem: \(uploads)/a.jpg]")
        #expect(prompt.text.isEmpty)
        #expect(prompt.imageCount == 1)
        #expect(prompt.imagePaths == ["\(uploads)/a.jpg"])
    }

    @Test func textWithoutMarkersStaysTheSame() {
        let text = "linha\n\n[imagem: /tmp/a.jpg]\n"
        let prompt = DemoImageMarkers.split(text)
        #expect(prompt.text == text)
        #expect(prompt.imageCount == 0)
        #expect(prompt.imagePaths.isEmpty)
    }

    @Test func echoedPromptCarriesTheUploadedPaths() async throws {
        let harness = try DemoHarness(
            DemoOptions(connectDelay: .milliseconds(5), echoDelay: .milliseconds(10), replyDelay: .milliseconds(50))
        )
        try await harness.connect()
        _ = try await harness.page("w1:p1")

        _ = try await harness.request(.sendPrompt(agentId: "w1:p1", text: "olha\n[imagem: \(uploads)/a.jpg]"))

        let echo = try await harness.messages.next()
        guard case .chatAppend(.agent("w1:p1"), let echoed) = echo.message else { throw UnexpectedMessage(envelope: echo) }
        #expect(echoed.map(\.kind) == [.userPrompt(text: "olha", imageCount: 1)])
        #expect(echoed.map(\.imagePaths) == [["\(uploads)/a.jpg"]])
    }

    @Test func demoAppChatShowsAnUploadAReadAndAMention() throws {
        let dataset = try DemoDataset.bundled()
        let chat = try #require(dataset.chats.first { $0.agentId == "w1:p1" })
        let withImages = chat.items.filter { !$0.imagePaths.isEmpty }
        #expect(withImages.map(\.kind.type) == ["userPrompt", "toolCall", "assistantText"])
        #expect(withImages.flatMap(\.imagePaths) == [
            "/Users/dev/Library/Application Support/Mocha/uploads/0b7c1e2a-5d4f-4a8b-9c3e-2f1a6b7c8d9e.jpg",
            "/Users/dev/projects/demo-app/docs/design/ajustes.png",
            "/Users/dev/projects/demo-app/build/prints/ajustes-depois.png",
        ])
    }
}
