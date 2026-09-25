import Foundation
import Testing
@testable import MochaDaemonCore

@Test func fixturesRootExists() {
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: Fixtures.root.path(percentEncoded: false), isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}

@Test func daemonVersionIsScaffoldVersion() {
    #expect(DaemonVersion.current == "0.1.0")
}
