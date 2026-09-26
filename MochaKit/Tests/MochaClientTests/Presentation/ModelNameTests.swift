import Testing
@testable import MochaClient

struct ModelNameTests {
    @Test(arguments: [
        ("claude-opus-5-5", "opus-5-5"),
        ("claude-haiku-4-5-20251001", "haiku-4-5"),
        ("claude-sonnet-4-5-20250929", "sonnet-4-5"),
        ("opus-5-5", "opus-5-5"),
        ("gpt-5-codex", "gpt-5-codex"),
        ("claude-fable-5-2024", "fable-5-2024"),
        ("", ""),
    ])
    func abbreviatesModel(model: String, expected: String) {
        #expect(ModelName.abbreviated(model) == expected)
    }
}
