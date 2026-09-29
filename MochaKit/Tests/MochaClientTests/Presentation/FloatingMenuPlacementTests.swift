import CoreGraphics
import MochaClient
import Testing

struct FloatingMenuPlacementTests {
    @Test func sitsAboveTheAnchorWhenItFits() {
        #expect(FloatingMenuPlacement.top(height: 200, preferredBottom: 700, minTop: 110, maxBottom: 800) == 500)
    }

    @Test func slidesDownOverTheKeyboardWhenTallerThanTheSpaceAbove() {
        let top = FloatingMenuPlacement.top(height: 400, preferredBottom: 440, minTop: 110, maxBottom: 800)
        #expect(top == 110)
        #expect(top + 400 <= 800)
    }

    @Test func pinsToTheTopLimitWhenTallerThanTheScreen() {
        #expect(FloatingMenuPlacement.top(height: 2_000, preferredBottom: 440, minTop: 110, maxBottom: 800) == 110)
        #expect(FloatingMenuPlacement.maxHeight(minTop: 110, maxBottom: 800) == 690)
        #expect(FloatingMenuPlacement.maxHeight(minTop: 900, maxBottom: 800) == 0)
    }
}
