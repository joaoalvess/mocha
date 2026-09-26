import Foundation
import Testing
@testable import MochaClient

struct ProvisioningProfileTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        return calendar
    }

    private static func date(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    private static func embeddedProfile(expiring expiration: Date) throws -> Data {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Name": "iOS Team Provisioning Profile", "ExpirationDate": expiration],
            format: .xml,
            options: 0
        )
        var data = Data([0x30, 0x82, 0x3A, 0x10, 0x06, 0x09, 0x2A, 0x86])
        data.append(plist)
        data.append(Data([0xA0, 0x82, 0x0D, 0x3C, 0x00, 0xFF]))
        return data
    }

    @Test func readsTheExpirationDateFromTheSignedProfile() throws {
        let expiration = try Self.date("2027-09-25T21:04:05Z")
        let profile = try #require(ProvisioningProfile(embeddedProfile: Self.embeddedProfile(expiring: expiration)))
        #expect(profile.expirationDate == expiration)
    }

    @Test func rejectsDataWithoutAPlist() {
        #expect(ProvisioningProfile(embeddedProfile: Data("not a profile".utf8)) == nil)
    }

    @Test func warnsBelowSevenDays() throws {
        let now = try Self.date("2026-09-26T12:00:00Z")
        let soon = ProvisioningProfile(expirationDate: try Self.date("2026-10-01T12:00:00Z"))
        let later = ProvisioningProfile(expirationDate: try Self.date("2026-10-03T12:00:00Z"))
        #expect(soon.daysLeft(now: now, calendar: Self.calendar) == 5)
        #expect(soon.isExpiringSoon(now: now, calendar: Self.calendar))
        #expect(soon.text(now: now, calendar: Self.calendar) == "vence em 5 dias")
        #expect(!later.isExpiringSoon(now: now, calendar: Self.calendar))
        #expect(later.text(now: now, calendar: Self.calendar) == "vence em 03/10/2026")
    }

    @Test func describesTheLastDays() throws {
        let now = try Self.date("2026-09-26T12:00:00Z")
        #expect(ProvisioningProfile(expirationDate: try Self.date("2026-09-27T12:00:00Z")).text(now: now, calendar: Self.calendar) == "vence amanhã")
        #expect(ProvisioningProfile(expirationDate: try Self.date("2026-09-26T20:00:00Z")).text(now: now, calendar: Self.calendar) == "vence hoje")
        #expect(ProvisioningProfile(expirationDate: try Self.date("2026-09-25T12:00:00Z")).text(now: now, calendar: Self.calendar) == "vencido")
    }
}
