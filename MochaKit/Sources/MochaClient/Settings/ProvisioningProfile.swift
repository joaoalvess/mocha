import Foundation

public struct ProvisioningProfile: Sendable, Equatable {
    public static let warningDays = 7

    public var expirationDate: Date

    public init(expirationDate: Date) {
        self.expirationDate = expirationDate
    }

    public init?(embeddedProfile data: Data) {
        let start = Data("<?xml".utf8)
        let end = Data("</plist>".utf8)
        guard
            let startRange = data.range(of: start),
            let endRange = data.range(of: end, in: startRange.lowerBound..<data.endIndex),
            let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: startRange.lowerBound..<endRange.upperBound),
                format: nil
            ) as? [String: Any],
            let expirationDate = plist["ExpirationDate"] as? Date
        else { return nil }
        self.init(expirationDate: expirationDate)
    }

    public func daysLeft(now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expirationDate)).day ?? 0
    }

    public func isExpiringSoon(now: Date, calendar: Calendar = .current) -> Bool {
        daysLeft(now: now, calendar: calendar) < Self.warningDays
    }

    public func text(now: Date, calendar: Calendar = .current) -> String {
        guard expirationDate > now else { return "vencido" }
        let days = daysLeft(now: now, calendar: calendar)
        switch days {
        case ..<1:
            return "vence hoje"
        case 1:
            return "vence amanhã"
        case ..<Self.warningDays:
            return "vence em \(days) dias"
        default:
            var style = Date.FormatStyle(date: .numeric, time: .omitted)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            style.locale = Locale(identifier: "pt_BR")
            return "vence em " + expirationDate.formatted(style)
        }
    }
}
