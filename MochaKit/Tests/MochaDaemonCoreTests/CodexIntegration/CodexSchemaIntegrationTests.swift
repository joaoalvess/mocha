import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.tags(.integration), .enabled(if: CodexLab.isEnabled))
struct CodexSchemaIntegrationTests {
    @Test func methodsAndItemTypesKeepEverythingFromTheValidatedCopy() throws {
        let lab = try #require(CodexLab.current)
        let installed = try CodexSchemaSnapshot(
            codexVersion: lab.version,
            stable: CodexSchemaBundle(directory: lab.stableSchema).surface,
            experimental: CodexSchemaBundle(directory: lab.experimentalSchema).surface
        )
        try installed.write(to: lab.schemaSnapshot)
        let validated = try CodexSchemaSnapshot(contentsOf: Fixtures.url("codex/schema/methods.json"))
        for (name, old, new) in [("estável", validated.stable, installed.stable), ("experimental", validated.experimental, installed.experimental)] {
            for (before, after) in zip(old.categories, new.categories) {
                let removed = Set(before.values).subtracting(after.values).sorted()
                let added = Set(after.values).subtracting(before.values).sorted()
                #expect(removed.isEmpty, "schema \(name) da \(lab.version): \(before.name) sumiram desde a \(validated.codexVersion): \(removed)")
                if !added.isEmpty {
                    print("schema \(name) da \(lab.version): \(before.name) novos desde a \(validated.codexVersion): \(added)")
                }
            }
        }
    }
}
