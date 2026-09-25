import Foundation

struct HttpRequestHead: Sendable, Equatable {
    enum ParseError: Error, Equatable {
        case malformed
        case unsupportedVersion

        var status: HttpStatus {
            switch self {
            case .malformed: .badRequest
            case .unsupportedVersion: .httpVersionNotSupported
            }
        }
    }

    enum ContentLength: Equatable {
        case absent
        case value(Int)
        case invalid
    }

    let method: HttpMethod
    let path: String
    let query: String?
    let version: String
    let headers: HttpHeaders

    var contentLength: ContentLength {
        let values = headers.values(for: "Content-Length")
        guard !values.isEmpty else { return .absent }
        var length: Int?
        for item in values.flatMap({ $0.split(separator: ",", omittingEmptySubsequences: false) }) {
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  trimmed.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                  let parsed = Int(trimmed)
            else { return .invalid }
            if let length, length != parsed { return .invalid }
            length = parsed
        }
        return length.map(ContentLength.value) ?? .invalid
    }

    static func endOfHead(in buffer: [UInt8], searchingFrom start: Int) -> Int? {
        var index = max(start, 0)
        while index + 4 <= buffer.count {
            if buffer[index] == 0x0D, buffer[index + 1] == 0x0A, buffer[index + 2] == 0x0D, buffer[index + 3] == 0x0A {
                return index
            }
            index += 1
        }
        return nil
    }

    static func parse(_ bytes: ArraySlice<UInt8>) -> Result<HttpRequestHead, ParseError> {
        guard let lines = splitLines(bytes), let requestLine = lines.first else { return .failure(.malformed) }
        let parts = requestLine.split(separator: 0x20, omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return .failure(.malformed) }
        guard parts[0].allSatisfy(isTokenByte), parts[1].allSatisfy({ (0x21...0x7E).contains($0) }) else {
            return .failure(.malformed)
        }
        let version = String(decoding: parts[2], as: UTF8.self)
        if let failure = validate(version: version) { return .failure(failure) }
        guard let target = splitTarget(String(decoding: parts[1], as: UTF8.self)) else { return .failure(.malformed) }
        var headers = HttpHeaders()
        for line in lines.dropFirst() {
            guard let field = parseField(line) else { return .failure(.malformed) }
            headers.add(field.name, field.value)
        }
        return .success(HttpRequestHead(
            method: HttpMethod(rawValue: String(decoding: parts[0], as: UTF8.self)),
            path: target.path,
            query: target.query,
            version: version,
            headers: headers
        ))
    }

    static func isTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: true
        case 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E: true
        default: false
        }
    }

    private static func isFieldValueByte(_ byte: UInt8) -> Bool {
        byte == 0x09 || (0x20...0x7E).contains(byte) || byte >= 0x80
    }

    private static func splitLines(_ bytes: ArraySlice<UInt8>) -> [ArraySlice<UInt8>]? {
        var lines: [ArraySlice<UInt8>] = []
        var lineStart = bytes.startIndex
        var index = bytes.startIndex
        while index < bytes.endIndex {
            switch bytes[index] {
            case 0x0D:
                guard index + 1 < bytes.endIndex, bytes[index + 1] == 0x0A else { return nil }
                lines.append(bytes[lineStart..<index])
                index += 2
                lineStart = index
            case 0x0A, 0x00:
                return nil
            default:
                index += 1
            }
        }
        lines.append(bytes[lineStart..<bytes.endIndex])
        return lines
    }

    private static func validate(version: String) -> ParseError? {
        if version == "HTTP/1.1" || version == "HTTP/1.0" { return nil }
        let bytes = Array(version.utf8)
        let looksLikeHttp = bytes.count == 8
            && version.hasPrefix("HTTP/")
            && (0x30...0x39).contains(bytes[5])
            && bytes[6] == 0x2E
            && (0x30...0x39).contains(bytes[7])
        return looksLikeHttp ? .unsupportedVersion : .malformed
    }

    private static func splitTarget(_ target: String) -> (path: String, query: String?)? {
        var originForm = Substring(target)
        if !target.hasPrefix("/") {
            let lowercased = target.lowercased()
            guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://"),
                  let schemeEnd = target.range(of: "://")
            else { return nil }
            let authorityAndRest = target[schemeEnd.upperBound...]
            guard let pathStart = authorityAndRest.firstIndex(where: { $0 == "/" || $0 == "?" }) else {
                return ("/", nil)
            }
            originForm = authorityAndRest[pathStart...]
        }
        let withoutFragment = originForm.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let pieces = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = pieces.first.map(String.init) ?? ""
        let query = pieces.count > 1 ? String(pieces[1]) : nil
        return (path.isEmpty ? "/" : path, query)
    }

    private static func parseField(_ line: ArraySlice<UInt8>) -> HttpHeaders.Field? {
        guard let first = line.first, first != 0x20, first != 0x09,
              let colon = line.firstIndex(of: 0x3A)
        else { return nil }
        let name = line[line.startIndex..<colon]
        guard !name.isEmpty, name.allSatisfy(isTokenByte) else { return nil }
        var value = line[(colon + 1)...]
        while let byte = value.first, byte == 0x20 || byte == 0x09 {
            value = value.dropFirst()
        }
        while let byte = value.last, byte == 0x20 || byte == 0x09 {
            value = value.dropLast()
        }
        guard value.allSatisfy(isFieldValueByte) else { return nil }
        return HttpHeaders.Field(name: String(decoding: name, as: UTF8.self), value: String(decoding: value, as: UTF8.self))
    }
}
