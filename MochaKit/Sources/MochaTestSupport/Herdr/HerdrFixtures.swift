import Foundation

public enum HerdrFixtures {
    public static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/herdr", directoryHint: .isDirectory)

    public static func url(_ name: String) -> URL {
        directory.appending(path: name)
    }

    public static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    public static func compactLine(_ name: String) throws -> Data {
        try compact(data(name))
    }

    public static func lines(_ name: String) throws -> [Data] {
        try data(name)
            .split(separator: 0x0A)
            .map { Data($0) }
            .filter { !$0.isEmpty }
    }

    public static func compact(_ json: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    public static func allNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }
}
