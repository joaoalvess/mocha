import Foundation

public enum HTMLTitle {
    public static let byteLimit = 64 * 1024

    private static let namedEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": " ",
    ]

    public static func extract(from data: Data) -> String? {
        let bytes = Array(data.prefix(byteLimit))
        guard let open = openingTagEnd(in: bytes),
              let close = find(Array("</title".utf8), in: bytes, from: open)
        else { return nil }
        let raw = String(decoding: bytes[open..<close], as: UTF8.self)
        let title = decodeEntities(raw).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : title
    }

    static func decodeEntities(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            let candidate = rest[afterAmpersand...].prefix(12)
            if let semicolon = candidate.firstIndex(of: ";"), let decoded = entity(String(candidate[..<semicolon])) {
                result += decoded
                rest = rest[rest.index(after: semicolon)...]
            } else {
                result += "&"
                rest = rest[afterAmpersand...]
            }
        }
        result += rest
        return result
    }

    private static func entity(_ name: String) -> String? {
        if let named = namedEntities[name] { return named }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value: UInt32?
        if digits.first == "x" || digits.first == "X" {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits, radix: 10)
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    private static func openingTagEnd(in bytes: [UInt8]) -> Int? {
        let tag = Array("<title".utf8)
        var start = 0
        while let found = find(tag, in: bytes, from: start) {
            let next = found + tag.count
            guard next < bytes.count else { return nil }
            let following = bytes[next]
            if following == UInt8(ascii: ">") || endsTagName(following) {
                guard let end = bytes[next...].firstIndex(of: UInt8(ascii: ">")) else { return nil }
                return end + 1
            }
            start = next
        }
        return nil
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard needle.count <= bytes.count, start <= bytes.count - needle.count else { return nil }
        for index in start...(bytes.count - needle.count) {
            var matches = true
            for offset in needle.indices where lowercased(bytes[index + offset]) != needle[offset] {
                matches = false
                break
            }
            if matches { return index }
        }
        return nil
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private static func endsTagName(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C || byte == UInt8(ascii: "/")
    }
}
