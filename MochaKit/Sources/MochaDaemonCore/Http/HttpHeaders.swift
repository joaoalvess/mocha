import Foundation

public struct HttpHeaders: Sendable, Equatable, Sequence, ExpressibleByDictionaryLiteral {
    public struct Field: Sendable, Equatable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public private(set) var fields: [Field]

    public init(_ fields: [Field] = []) {
        self.fields = fields
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        self.fields = elements.map { Field(name: $0.0, value: $0.1) }
    }

    public subscript(name: String) -> String? {
        fields.first { Self.matches($0.name, name) }?.value
    }

    public func values(for name: String) -> [String] {
        fields.filter { Self.matches($0.name, name) }.map(\.value)
    }

    public func contains(_ name: String) -> Bool {
        fields.contains { Self.matches($0.name, name) }
    }

    public func tokens(for name: String) -> [String] {
        values(for: name)
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    public mutating func add(_ name: String, _ value: String) {
        fields.append(Field(name: name, value: value))
    }

    public mutating func set(_ name: String, _ value: String) {
        remove(name)
        add(name, value)
    }

    public mutating func remove(_ name: String) {
        fields.removeAll { Self.matches($0.name, name) }
    }

    public func makeIterator() -> IndexingIterator<[Field]> {
        fields.makeIterator()
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }
}
