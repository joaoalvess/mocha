import Foundation
import MochaTranscript
import Testing

@Suite
struct PlainTextTests {
    private func preview(_ markdown: String) -> String {
        PlainText.preview(fromMarkdown: markdown)
    }

    @Test func codeFencesAreRemovedAndTheirContentKept() {
        #expect(preview("Rode:\n```bash\nnpm test -- --watch\n```\nPronto.") == "Rode: npm test -- --watch Pronto.")
        #expect(preview("~~~\nlet x = 1\n~~~") == "let x = 1")
        #expect(preview("````md\n```\ndentro\n```\n````") == "``` dentro ```")
        #expect(preview("```swift\nsem fechamento **fica**") == "sem fechamento **fica**")
    }

    @Test func inlineCodeLosesItsBackticksAndKeepsItsContent() {
        #expect(preview("Use `git status` e ``a ` b``.") == "Use git status e a ` b.")
        #expect(preview("O campo `tool_use_id` e `*ptr`") == "O campo tool_use_id e *ptr")
        #expect(preview("```ls -la```") == "ls -la")
        #expect(preview("crase solta ` aqui") == "crase solta aqui")
    }

    @Test func emphasisMarkersAreRemoved() {
        #expect(preview("**negrito**, *itálico*, __forte__, _leve_ e ~~riscado~~") == "negrito, itálico, forte, leve e riscado")
        #expect(preview("***tudo***") == "tudo")
        #expect(preview("snake_case_name e 2 * 3 e ~/pasta") == "snake_case_name e 2 * 3 e ~/pasta")
    }

    @Test func headingQuoteAndListMarkersAreRemoved() {
        #expect(preview("# Título\n## Seção\n###### Fundo") == "Título Seção Fundo")
        #expect(preview("#hashtag e ####### sete") == "#hashtag e ####### sete")
        #expect(preview("> citação\n> > aninhada") == "citação aninhada")
        #expect(preview("- um\n* dois\n+ três\n  - quatro") == "um dois três quatro")
        #expect(preview("1. primeiro\n2) segundo\n10. décimo") == "primeiro segundo décimo")
        #expect(preview("> - item citado") == "item citado")
        #expect(preview("-sem espaço e 3.14") == "-sem espaço e 3.14")
    }

    @Test func linksKeepOnlyTheirText() {
        #expect(preview("Veja [a doc](https://example.com/docs) e ![o print](img.png).") == "Veja a doc e o print.")
        #expect(preview("[**forte**](https://x.dev/a_(b))") == "forte")
        #expect(preview("[x] tarefa e [sem link]") == "[x] tarefa e [sem link]")
    }

    @Test func escapedCharactersStayLiteral() {
        #expect(preview("\\*não é ênfase\\* e \\# nem título") == "*não é ênfase* e # nem título")
    }

    @Test func whitespaceCollapsesIntoSingleSpaces() {
        #expect(preview("  várias\n\n\tlinhas   e\r\n espaços  ") == "várias linhas e espaços")
        #expect(preview("\n\n   \n") == "")
    }

    @Test func textIsCutAt200CharactersWithoutEllipsis() {
        let long = String(repeating: "á", count: 250)
        #expect(preview(long) == String(repeating: "á", count: 200))
        let words = String(repeating: "palavra ", count: 40)
        let cut = preview(words)
        #expect(cut.count <= 200)
        #expect(!cut.hasSuffix(" "))
        #expect(!cut.hasSuffix("…"))
        #expect(cut == String(String(repeating: "palavra ", count: 25).dropLast()))
        #expect(PlainText.preview(fromMarkdown: "**abc** def", limit: 5) == "abc d")
        #expect(PlainText.previewLimit == 200)
    }

    @Test func emojiAndAccentsCountAsSingleCharacters() {
        let text = String(repeating: "👩🏽‍💻", count: 201)
        #expect(preview(text).count == 200)
    }
}
