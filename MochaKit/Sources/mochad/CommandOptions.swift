struct CommandOptions {
    struct UsageError: Error, CustomStringConvertible {
        let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    private(set) var positional: [String] = []
    private var values: [String: String] = [:]
    private var presentFlags: Set<String> = []

    init(_ arguments: [String], flags: Set<String>) throws {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if flags.contains(argument) {
                presentFlags.insert(argument)
            } else if argument.hasPrefix("--") {
                let next = arguments.index(after: index)
                guard next < arguments.endIndex else { throw UsageError("\(argument) precisa de um valor") }
                values[argument] = arguments[next]
                index = next
            } else {
                positional.append(argument)
            }
            index = arguments.index(after: index)
        }
    }

    var names: Set<String> {
        Set(values.keys).union(presentFlags)
    }

    func value(_ name: String) -> String? {
        values[name]
    }

    func has(_ flag: String) -> Bool {
        presentFlags.contains(flag)
    }

    func required(_ name: String) throws -> String {
        guard let value = values[name] else { throw UsageError("falta \(name)") }
        return value
    }

    func integer(_ name: String) throws -> Int? {
        guard let text = values[name] else { return nil }
        guard let value = Int(text) else { throw UsageError("\(name) precisa ser um número inteiro") }
        return value
    }
}
