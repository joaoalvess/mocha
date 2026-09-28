import Foundation
import Testing
@testable import MochaDaemonCore

struct HTMLTitleTests {
    @Test func decodesBasicEntitiesAndCollapsesWhitespace() {
        let html = "<html><head><title>\n  Portal &amp; &lt;Cliente&gt;\t&quot;v2&quot; &#39;a&#x27;&apos;&nbsp;fim  </title></head></html>"
        #expect(HTMLTitle.extract(from: Data(html.utf8)) == "Portal & <Cliente> \"v2\" 'a'' fim")
    }

    @Test func keepsUnknownEntitiesAndLoneAmpersands() {
        let html = "<title>A & B &copy; &#xZZ; &#233;</title>"
        #expect(HTMLTitle.extract(from: Data(html.utf8)) == "A & B &copy; &#xZZ; é")
    }

    @Test func matchesTagCaseInsensitivelyWithAttributes() {
        let html = #"<HEAD><TITLE lang="pt">Início</TITLE></HEAD>"#
        #expect(HTMLTitle.extract(from: Data(html.utf8)) == "Início")
    }

    @Test func ignoresTagsThatOnlyStartWithTitle() {
        let html = "<titlebar>Não</titlebar><title>Sim</title>"
        #expect(HTMLTitle.extract(from: Data(html.utf8)) == "Sim")
    }

    @Test func missingOrEmptyTitleIsNil() {
        #expect(HTMLTitle.extract(from: Data("<html><body>oi</body></html>".utf8)) == nil)
        #expect(HTMLTitle.extract(from: Data("<title>   </title>".utf8)) == nil)
        #expect(HTMLTitle.extract(from: Data("<title>sem fechamento".utf8)) == nil)
        #expect(HTMLTitle.extract(from: Data()) == nil)
    }

    @Test func readsOnlyTheFirst64KB() {
        let filler = String(repeating: "a", count: HTMLTitle.byteLimit)
        let inside = "<title>Dentro</title>" + filler
        let outside = "<body>" + filler + "<title>Fora</title>"
        let straddling = String(repeating: "a", count: HTMLTitle.byteLimit - 10) + "<title>Cortado</title>"
        #expect(HTMLTitle.extract(from: Data(inside.utf8)) == "Dentro")
        #expect(HTMLTitle.extract(from: Data(outside.utf8)) == nil)
        #expect(HTMLTitle.extract(from: Data(straddling.utf8)) == nil)
    }
}
