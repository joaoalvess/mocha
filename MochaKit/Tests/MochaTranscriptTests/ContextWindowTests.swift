import Foundation
import MochaTranscript
import Testing

@Suite
struct ContextWindowTests {
    @Test(arguments: [
        "claude-opus-4-7",
        "claude-opus-4-8",
        "claude-opus-4-10",
        "claude-opus-4-7-20260301",
        "claude-opus-5",
        "claude-opus-5-5",
        "claude-fable-1",
        "claude-fable",
        "claude-sonnet-5",
        "claude-sonnet-5-1-20261001",
        "Claude-Opus-5-5",
    ])
    func extendedModelsHaveAMillionTokens(_ model: String) {
        #expect(ContextWindow.size(forModel: model) == 1_000_000)
    }

    @Test(arguments: [
        "claude-opus-4-6",
        "claude-opus-4-5-20251101",
        "claude-opus-4-1-20250805",
        "claude-opus-4-20250514",
        "claude-opus-4",
        "claude-sonnet-4-5-20250929",
        "claude-haiku-4-5-20251001",
        "claude-3-7-sonnet-20250219",
        "<synthetic>",
        "",
    ])
    func otherModelsHaveTwoHundredThousandTokens(_ model: String) {
        #expect(ContextWindow.size(forModel: model) == 200_000)
    }
}
