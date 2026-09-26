import Foundation
import Testing
@testable import MochaDaemonCore

struct HttpRequestHeadTests {
    private static func parse(_ raw: String) -> Result<HttpRequestHead, HttpRequestHead.ParseError> {
        let bytes = Array(raw.utf8)
        let end = HttpRequestHead.endOfHead(in: bytes, searchingFrom: 0) ?? bytes.count
        return HttpRequestHead.parse(bytes[..<end])
    }

    @Test func parsesRequestLineHeadersAndQuery() throws {
        let head = try Self.parse(
            "POST /hooks/Stop?session=abc&x=1 HTTP/1.1\r\nHost: 127.0.0.1:47420\r\nX-Mocha-Pane:  w1-p2 \r\nContent-Length: 12\r\n\r\n"
        ).get()
        #expect(head.method == .post)
        #expect(head.path == "/hooks/Stop")
        #expect(head.query == "session=abc&x=1")
        #expect(head.version == "HTTP/1.1")
        #expect(head.headers["x-mocha-pane"] == "w1-p2")
        #expect(head.headers["HOST"] == "127.0.0.1:47420")
        #expect(head.contentLength == .value(12))
    }

    @Test func pathWithoutQueryHasNilQueryAndEmptyQueryIsKept() throws {
        #expect(try Self.parse("GET /v1 HTTP/1.1\r\n\r\n").get().query == nil)
        #expect(try Self.parse("GET /v1? HTTP/1.1\r\n\r\n").get().query == "")
    }

    @Test func absoluteFormIsReducedToPathAndQuery() throws {
        let head = try Self.parse("GET https://mac.tailnet.ts.net/v1/health?probe=1 HTTP/1.1\r\n\r\n").get()
        #expect(head.path == "/v1/health")
        #expect(head.query == "probe=1")
        #expect(try Self.parse("GET http://mac.tailnet.ts.net HTTP/1.1\r\n\r\n").get().path == "/")
    }

    @Test func versionsAreClassified() {
        #expect(throws: Never.self) { try Self.parse("GET / HTTP/1.0\r\n\r\n").get() }
        #expect(Self.parse("GET / HTTP/2.0\r\n\r\n") == .failure(.unsupportedVersion))
        #expect(Self.parse("GET / HTTX/1.1\r\n\r\n") == .failure(.malformed))
    }

    @Test(arguments: [
        ("absent", nil, HttpRequestHead.ContentLength.absent),
        ("single", "10", .value(10)),
        ("repeated equal list", "10, 10", .value(10)),
        ("conflicting list", "10, 11", .invalid),
        ("negative", "-1", .invalid),
        ("signed", "+1", .invalid),
        ("not a number", "abc", .invalid),
        ("overflow", "99999999999999999999999", .invalid),
    ] as [(String, String?, HttpRequestHead.ContentLength)])
    func contentLengthIsParsedStrictly(_ label: String, _ value: String?, _ expected: HttpRequestHead.ContentLength) throws {
        let header = value.map { "Content-Length: \($0)\r\n" } ?? ""
        let head = try Self.parse("POST /x HTTP/1.1\r\n\(header)\r\n").get()
        #expect(head.contentLength == expected, "\(label)")
    }

    @Test func headersKeepOrderAndRepeatedValues() throws {
        let head = try Self.parse("GET / HTTP/1.1\r\nAccept: a\r\naccept: b\r\nConnection: keep-alive, Upgrade\r\n\r\n").get()
        #expect(head.headers.values(for: "ACCEPT") == ["a", "b"])
        #expect(head.headers.tokens(for: "connection") == ["keep-alive", "upgrade"])
    }

    @Test func responseSerializationManagesFramingHeaders() {
        let response = HttpResponse(
            status: .ok,
            headers: ["Content-Length": "999", "Connection": "keep-alive", "X-Bad": "a\r\nInjected: 1", "X-Good": "ok"],
            body: Data("abc".utf8)
        )
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text == "HTTP/1.1 200 OK\r\nX-Good: ok\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc")
    }

    @Test func noContentResponseHasNoBodyFraming() {
        let text = String(decoding: HttpResponse(status: .noContent, body: Data("x".utf8)).serialized(), as: UTF8.self)
        #expect(text == "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
    }

    @Test func routerDistinguishesUnknownPathFromWrongMethod() {
        var router = HttpRouter()
        router.route(.post, "/v1/respond") { _ in HttpResponse() }
        router.webSocket("/v1") { _, _ in }
        guard case .notFound = router.resolve(.get, "/v1/other") else {
            Issue.record("expected notFound")
            return
        }
        guard case .methodNotAllowed(let allowed) = router.resolve(.get, "/v1/respond") else {
            Issue.record("expected methodNotAllowed")
            return
        }
        #expect(allowed == [.post])
        guard case .endpoint(.webSocket) = router.resolve(.get, "/v1") else {
            Issue.record("expected webSocket endpoint")
            return
        }
    }

    @Test func queryItemsAreDecoded() {
        let request = HttpRequest(method: .get, path: "/x", query: "a=1&name=Jo%C3%A3o&flag")
        #expect(request.queryItems.map(\.name) == ["a", "name", "flag"])
        #expect(request.queryItems[1].value == "João")
    }
}

struct WebSocketFrameTests {
    private static let unlimited = Int.max

    @Test func acceptValueMatchesRFC6455Example() {
        #expect(WebSocketHandshake.acceptValue(for: RawClient.sampleKey) == RawClient.sampleAccept)
    }

    @Test func decodesMaskedFramesOfEveryLengthEncoding() {
        for length in [0, 125, 126, 65535, 65536, 70000] {
            let payload = (0..<length).map { UInt8(truncatingIfNeeded: $0) }
            let bytes = RawFrameBuilder.frame(opcode: 0x2, payload: payload)
            #expect(
                WebSocketFrame.decode(bytes, from: 0, maxDataPayload: Self.unlimited)
                    == .frame(WebSocketFrame(isFinal: true, opcode: .binary, payload: payload), consumed: bytes.count)
            )
        }
    }

    @Test func decodesFromOffsetAndReportsIncompleteFrames() {
        let first = RawFrameBuilder.text("one")
        let second = RawFrameBuilder.text("two", isFinal: false)
        let buffer = first + second
        #expect(
            WebSocketFrame.decode(buffer, from: first.count, maxDataPayload: Self.unlimited)
                == .frame(WebSocketFrame(isFinal: false, opcode: .text, payload: Array("two".utf8)), consumed: second.count)
        )
        for cut in 0..<second.count {
            #expect(WebSocketFrame.decode(Array(second[..<cut]), from: 0, maxDataPayload: Self.unlimited) == .incomplete)
        }
    }

    @Test func rejectsProtocolViolations() {
        let violations: [[UInt8]] = [
            RawFrameBuilder.frame(opcode: 0x1, payload: [0x61], mask: nil),
            [0xC1, 0x80, 0, 0, 0, 0],
            [0x83, 0x80, 0, 0, 0, 0],
            [0x0B, 0x80, 0, 0, 0, 0],
            RawFrameBuilder.frame(opcode: 0x9, payload: [], isFinal: false),
            RawFrameBuilder.frame(opcode: 0x9, payload: [UInt8](repeating: 0, count: 126)),
            [0x82, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4],
        ]
        for bytes in violations {
            #expect(WebSocketFrame.decode(bytes, from: 0, maxDataPayload: Self.unlimited) == .violation(.protocolError))
        }
    }

    @Test func oversizedDataFrameIsRejectedFromItsHeaderAlone() {
        let header = Array(RawFrameBuilder.frame(opcode: 0x2, payload: [UInt8](repeating: 0, count: 70000)).prefix(14))
        #expect(WebSocketFrame.decode(header, from: 0, maxDataPayload: 65536) == .violation(.messageTooBig))
    }

    @Test func encodesUnmaskedServerFrames() {
        let short = WebSocketFrame.encode(.text, payload: Array("hi".utf8))
        #expect(Array(short) == [0x81, 0x02, 0x68, 0x69])
        let medium = WebSocketFrame.encode(.binary, payload: [UInt8](repeating: 1, count: 300))
        #expect(Array(medium.prefix(4)) == [0x82, 126, 0x01, 0x2C])
        let long = WebSocketFrame.encode(.binary, payload: [UInt8](repeating: 1, count: 70000))
        #expect(Array(long.prefix(10)) == [0x82, 127, 0, 0, 0, 0, 0, 0x01, 0x11, 0x70])
    }

    @Test func closePayloadsAreParsedAndValidated() {
        #expect(WebSocketFrame.parseClose([]) == .valid(nil, ""))
        #expect(WebSocketFrame.parseClose([0x03]) == .invalid(.protocolError))
        #expect(WebSocketFrame.parseClose([0x03, 0xE8] + Array("bye".utf8)) == .valid(.normalClosure, "bye"))
        #expect(WebSocketFrame.parseClose([0x03, 0xED]) == .invalid(.protocolError))
        #expect(WebSocketFrame.parseClose([0x0B, 0xB8]) == .valid(WebSocketCloseCode(rawValue: 3000), ""))
        #expect(WebSocketFrame.parseClose([0x03, 0xE8, 0xC3, 0x28]) == .invalid(.invalidPayload))
    }

    @Test func closeReasonIsTruncatedOnScalarBoundary() {
        let payload = WebSocketFrame.closePayload(code: .goingAway, reason: String(repeating: "é", count: 100))
        #expect(payload.count == 124)
        #expect(String(validating: payload[2...], as: UTF8.self) == String(repeating: "é", count: 61))
    }
}
