import Foundation
import Testing
@testable import MochaHerdr

@Test func fixturesRootExists() {
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: Fixtures.root.path(percentEncoded: false), isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}
