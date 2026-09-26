import Testing
@testable import MochaDemo

@Suite struct DemoImageMarkersTests {
    private let uploads = "/Users/demo/Library/Application Support/Mocha/uploads"

    @Test func markersLeaveTheTextAndCountAsImages() {
        let text = "olha esses prints\n[imagem: \(uploads)/a.jpg]\n[imagem: \(uploads)/b.jpg]"
        let prompt = DemoImageMarkers.split(text)
        #expect(prompt.text == "olha esses prints")
        #expect(prompt.imageCount == 2)
    }

    @Test func promptWithOnlyMarkersBecomesEmpty() {
        let prompt = DemoImageMarkers.split("[imagem: \(uploads)/a.jpg]")
        #expect(prompt.text.isEmpty)
        #expect(prompt.imageCount == 1)
    }

    @Test func textWithoutMarkersStaysTheSame() {
        let text = "linha\n\n[imagem: /tmp/a.jpg]\n"
        let prompt = DemoImageMarkers.split(text)
        #expect(prompt.text == text)
        #expect(prompt.imageCount == 0)
    }
}
