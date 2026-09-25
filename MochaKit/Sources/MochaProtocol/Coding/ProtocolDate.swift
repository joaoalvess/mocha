import Foundation

public enum ProtocolDate {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static let fractionalParser = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondParser = Date.ISO8601FormatStyle()

    public static func string(from date: Date) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        guard milliseconds.isFinite else { return date.ISO8601Format() }
        let wholeSeconds = (milliseconds / 1000).rounded(.down)
        let fraction = Int(milliseconds - wholeSeconds * 1000)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: wholeSeconds)
        )
        let datePart = [
            padded(components.year, width: 4),
            padded(components.month, width: 2),
            padded(components.day, width: 2),
        ].joined(separator: "-")
        let timePart = [
            padded(components.hour, width: 2),
            padded(components.minute, width: 2),
            padded(components.second, width: 2),
        ].joined(separator: ":")
        return "\(datePart)T\(timePart).\(padded(fraction, width: 3))Z"
    }

    public static func date(from string: String) -> Date? {
        if let date = try? fractionalParser.parse(string) {
            return date
        }
        return try? wholeSecondParser.parse(string)
    }

    private static func padded(_ value: Int?, width: Int) -> String {
        let digits = String(value ?? 0)
        guard digits.count < width else { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}

extension KeyedDecodingContainer {
    func decodeProtocolDate(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        guard let date = ProtocolDate.date(from: string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid ISO-8601 date: \(string)"
            )
        }
        return date
    }

    func decodeProtocolDateIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeProtocolDate(forKey: key)
    }
}

extension KeyedEncodingContainer {
    mutating func encodeProtocolDate(_ date: Date, forKey key: Key) throws {
        try encode(ProtocolDate.string(from: date), forKey: key)
    }

    mutating func encodeProtocolDateIfPresent(_ date: Date?, forKey key: Key) throws {
        guard let date else { return }
        try encodeProtocolDate(date, forKey: key)
    }
}
