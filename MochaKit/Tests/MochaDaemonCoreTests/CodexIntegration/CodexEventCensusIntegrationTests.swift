import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.tags(.integration), .enabled(if: CodexLab.isEnabled), .timeLimit(.minutes(4)))
struct CodexEventCensusIntegrationTests {
    @Test func everyFixtureFitsTheInstalledExperimentalSchema() throws {
        let lab = try #require(CodexLab.current)
        let schema = try CodexSchemaBundle(directory: lab.experimentalSchema)
        for fixture in try CodexFixture.all() {
            let node = fixture.isResponse ? schema.resultSchema(of: fixture.method) : schema.paramsSchema(of: fixture.method)
            guard let node else {
                Issue.record("\(fixture.name): \(fixture.method) não existe no schema da \(lab.version)")
                continue
            }
            let missing = schema.missingPaths(of: fixture.payload, in: node, at: fixture.label)
            #expect(missing.isEmpty, "\(fixture.name): campos da fixture fora do schema da \(lab.version): \(missing)")
        }
    }

    @Test func fixturesMatchTheLiveEventsOfTheCycle() async throws {
        let lab = try #require(CodexLab.current)
        let cycle = try await CodexLabCycle.shared.value
        var live: [String] = []
        var schemaOnly: [String] = []
        for fixture in try CodexFixture.all() {
            let samples = (fixture.isResponse
                ? [cycle.responses[fixture.method]].compactMap { $0 }
                : cycle.events.filter { $0.method == fixture.method }.map(\.params))
                .filter { CodexPayloadShape.isComparable($0, with: fixture.payload) }
            let compared = samples.map { sample in
                (sample: sample, missing: CodexPayloadShape.missingKeys(of: fixture.payload, in: sample, at: fixture.label))
            }
            guard let best = compared.min(by: { $0.missing.count < $1.missing.count }) else {
                schemaOnly.append(fixture.name)
                continue
            }
            live.append(fixture.name)
            #expect(best.missing.isEmpty, "\(fixture.name): campos que sumiram na \(lab.version): \(best.missing)\npayload real: \(best.sample.compactSerialized())")
            let added = CodexPayloadShape.missingKeys(of: best.sample, in: fixture.payload, at: fixture.label)
            if !added.isEmpty {
                print("censo: campos ao vivo na \(lab.version) que \(fixture.name) não tem: \(added)")
            }
        }
        let methods = Dictionary(cycle.events.map { ($0.method, 1) }, uniquingKeysWith: +)
        let items = cycle.events.compactMap { $0.params["item"]?["type"]?.stringValue }
            + (cycle.responses["thread/items/list"]?["data"]?.arrayValue ?? []).compactMap { $0["item"]?["type"]?.stringValue }
        print("censo: fixtures conferidas ao vivo \(live), só pelo schema \(schemaOnly)")
        print("censo: eventos ao vivo \(methods.sorted { $0.key < $1.key })")
        print("censo: itens ao vivo \(Dictionary(items.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.key < $1.key })")
        #expect(!live.isEmpty)
        let schema = try CodexSchemaBundle(directory: lab.experimentalSchema)
        let unknown = Set(methods.keys).subtracting(schema.serverMethods).subtracting(["mocha/disconnected"])
        #expect(unknown.isEmpty, "eventos ao vivo fora do schema da \(lab.version): \(unknown.sorted())")
    }
}
