private struct SkippedElement: Decodable {
    init(from decoder: any Decoder) throws {}
}

extension KeyedDecodingContainer {
    func decodeLossyArray<Element: Decodable>(of type: Element.Type, forKey key: Key) throws -> [Element] {
        var container = try nestedUnkeyedContainer(forKey: key)
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(SkippedElement.self)) == nil {
                break
            }
        }
        return elements
    }
}

func unknownTypeError(_ type: String, in codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: codingPath, debugDescription: "Unknown type: \(type)")
    )
}
