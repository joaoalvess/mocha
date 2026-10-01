import Foundation
import Testing
@testable import MochaTranscript

@Suite
struct ImageMentionsTests {
    private static let cwd = "/Users/dev/projects/demo-app"
    private static let home = "/Users/dev"

    private func paths(_ markdown: String, cwd: String? = ImageMentionsTests.cwd) -> [String] {
        ImageMentions.paths(in: markdown, cwd: cwd, home: Self.home)
    }

    @Test func absolutePathInBackticksStaysAsItIs() {
        #expect(paths("Salvei o print em `/tmp/shots/tela.png`.") == ["/tmp/shots/tela.png"])
        #expect(paths("`/private/tmp/a.png` e `/tmp/b.png`") == ["/private/tmp/a.png", "/tmp/b.png"])
    }

    @Test func relativePathInBackticksJoinsTheCwd() {
        #expect(paths("Veja `docs/tela-login.png`") == ["\(Self.cwd)/docs/tela-login.png"])
        #expect(paths("`./docs/./b.jpg` e `../outro/a.PNG`") == ["\(Self.cwd)/docs/b.jpg", "/Users/dev/projects/outro/a.PNG"])
        #expect(ImageMentions.paths(in: "`a.png`", cwd: "/Users/dev/projects/demo-app/", home: Self.home) == ["\(Self.cwd)/a.png"])
    }

    @Test func tildeUsesTheHome() {
        #expect(paths("`~/Desktop/print.heic` e ~/Downloads/foto.webp") == ["/Users/dev/Desktop/print.heic", "/Users/dev/Downloads/foto.webp"])
        #expect(ImageMentions.paths(in: "~/a.png", cwd: nil, home: "/Users/dev/") == ["/Users/dev/a.png"])
    }

    @Test func bareFileNameJoinsTheCwd() {
        #expect(paths("Gerei screenshot.png no projeto") == ["\(Self.cwd)/screenshot.png"])
        #expect(paths("Atualizei docs/referencias/moshi/chat-conversa.png\ne assets/icone.gif") == [
            "\(Self.cwd)/docs/referencias/moshi/chat-conversa.png",
            "\(Self.cwd)/assets/icone.gif",
        ])
    }

    @Test func linkAndImageTargetsAreCandidates() {
        #expect(paths("A [tela de login](docs/tela.png) mudou") == ["\(Self.cwd)/docs/tela.png"])
        #expect(paths("![captura](/tmp/captura.gif)") == ["/tmp/captura.gif"])
        #expect(paths(#"[print](docs/a.png "Título")"#) == ["\(Self.cwd)/docs/a.png"])
        #expect(paths("[print](<docs/meu print.png>)") == ["\(Self.cwd)/docs/meu print.png"])
        #expect(paths("[o arquivo](README.md) e [x](docs/(1).png)") == ["\(Self.cwd)/docs/(1).png"])
    }

    @Test func candidatesKeepTheOrderOfAppearance() {
        #expect(paths("Antes `a.png`, depois [b](b.png) e c.png; por fim `d.jpg`") == ["a.png", "b.png", "c.png", "d.jpg"].map { "\(Self.cwd)/\($0)" })
    }

    @Test func fencedBlocksAreIgnored() {
        let markdown = """
        Rodei:
        ```bash
        open /tmp/dentro.png
        cp a.png `b.png`
        ```
        e o resultado ficou em `fora.png`.
          ~~~
          /tmp/til.png
          ~~~
        ````
        ```
        /tmp/aninhado.png
        ````
        fim /tmp/fim.png
        """
        #expect(paths(markdown) == ["\(Self.cwd)/fora.png", "/tmp/fim.png"])
        #expect(paths("antes /tmp/a.png\n```\n/tmp/sem-fim.png") == ["/tmp/a.png"])
    }

    @Test func urlsAreIgnored() {
        #expect(paths("https://example.com/a.png e `file:///tmp/b.png` e [c](https://x.com/c.png) e http://h/d.jpg.").isEmpty)
    }

    @Test func trailingPunctuationLeavesTheCandidate() {
        #expect(paths("Pronto: /tmp/a.png. (veja /tmp/b.jpg) /tmp/c.jpeg, /tmp/d.gif?! /tmp/e.webp;: /tmp/f.heif).") == [
            "/tmp/a.png", "/tmp/b.jpg", "/tmp/c.jpeg", "/tmp/d.gif", "/tmp/e.webp", "/tmp/f.heif",
        ])
        #expect(paths("`/tmp/g.png.`") == ["/tmp/g.png"])
    }

    @Test func emphasisQuotesAndOpeningParenthesisLeaveTheCandidate() {
        #expect(paths("(veja docs/a.png) **/tmp/b.png** \"/tmp/c.jpg\" '/tmp/d.gif'") == [
            "\(Self.cwd)/docs/a.png", "/tmp/b.png", "/tmp/c.jpg", "/tmp/d.gif",
        ])
    }

    @Test func extensionsIgnoreCaseAndOtherFilesAreSkipped() {
        #expect(paths("/tmp/A.JPG /tmp/b.HeIc /tmp/c.Webp") == ["/tmp/A.JPG", "/tmp/b.HeIc", "/tmp/c.Webp"])
        #expect(paths("`main.swift` arquivo.pngx /tmp/a.png/b `.png` /tmp/.jpg notes.txt png").isEmpty)
    }

    @Test func atMostSixPathsPerItem() {
        let markdown = (1...8).map { "`/tmp/\($0).png`" }.joined(separator: " ")
        #expect(paths(markdown) == (1...6).map { "/tmp/\($0).png" })
    }

    @Test func repeatedPathsAppearOnceInOrder() {
        #expect(paths("`b.png` a.png b.png \(Self.cwd)/a.png `./b.png`") == ["\(Self.cwd)/b.png", "\(Self.cwd)/a.png"])
        let repeated = Array(repeating: "`/tmp/a.png`", count: 7).joined(separator: " ") + " /tmp/b.png"
        #expect(paths(repeated) == ["/tmp/a.png", "/tmp/b.png"])
    }

    @Test func relativeCandidatesNeedACwd() {
        #expect(paths("`docs/a.png` /tmp/b.png ~/c.png d.png", cwd: nil) == ["/tmp/b.png", "/Users/dev/c.png"])
        #expect(paths("`docs/a.png`", cwd: "").isEmpty)
    }

    @Test func quickCheckLooksForADotAndAnImageExtension() {
        #expect(ImageMentions.mayMentionImage("nada aqui. só texto, `código` e https://x.com") == false)
        #expect(ImageMentions.mayMentionImage("x.PnG"))
        #expect(ImageMentions.mayMentionImage("a.jpeg"))
        #expect(ImageMentions.mayMentionImage(".pn") == false)
    }

    @Test func imageExtensionNeedsAFileName() {
        #expect(ImageFileExtension.matches("/tmp/a.png"))
        #expect(ImageFileExtension.matches("b.HEIF"))
        #expect(ImageFileExtension.matches(".png") == false)
        #expect(ImageFileExtension.matches("/tmp/.png") == false)
        #expect(ImageFileExtension.matches("/tmp/a.png/b") == false)
        #expect(ImageFileExtension.matches("/tmp/a.txt") == false)
        #expect(ImageFileExtension.matches("/tmp/png") == false)
    }
}
