import Foundation
import Testing
@testable import MochaDaemonCore

@Suite
struct UsageDoctorCheckTests {
    static let cachePath = ".local/state/herdr/plugins/herdr-agent-usage/claude-statusline.json"

    @Test func usagePathsAreUnderTheHome() async throws {
        try await withTemporaryHome { home async throws in
            #expect(home.paths.usageCacheFile == home.url.appending(path: Self.cachePath))
            #expect(home.paths.claudeAccountFile == home.url.appending(path: ".claude.json"))
        }
    }

    @Test func usageItemShowsTheCacheAge() async throws {
        try await withTemporaryHome { home async throws in
            try home.write(String(decoding: try Fixtures.data(UsageSample.cacheFixture), as: UTF8.self), to: Self.cachePath)
            let item = DoctorChecks.usage(home.paths, now: UsageSample.fetchedAt.addingTimeInterval(180))
            #expect(item == DoctorItem("Uso", .ok, "cache atualizado há 3 min · 5h 12% · 7d 71%", details: ["~/\(Self.cachePath)"]))
            let fresh = DoctorChecks.usage(home.paths, now: UsageSample.fetchedAt.addingTimeInterval(20))
            #expect(fresh.summary.hasPrefix("cache atualizado há menos de 1 min"))
        }
    }

    @Test func usageItemWarnsWithoutTheCache() async throws {
        try await withTemporaryHome { home async throws in
            let item = DoctorChecks.usage(home.paths, now: UsageSample.fetchedAt)
            #expect(item == DoctorItem("Uso", .warning, "sem o cache do plugin herdr-agent-usage", details: ["esperado em ~/\(Self.cachePath)"]))
        }
    }

    @Test func usageItemWarnsOnAnInvalidCache() async throws {
        try await withTemporaryHome { home async throws in
            try home.write("não é json", to: Self.cachePath)
            let item = DoctorChecks.usage(home.paths, now: UsageSample.fetchedAt)
            #expect(item.status == .warning)
            #expect(item.summary == "cache do plugin herdr-agent-usage inválido")
        }
    }
}
