import Foundation

enum Console {
    static func line(_ text: String = "") {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    static func fail(_ message: String, code: Int32 = 1) -> Int32 {
        error(message)
        return code
    }

    static func timestamp(_ date: Date = Date()) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

extension CommandOptions {
    static func parse(_ arguments: [String], flags: Set<String> = [], allowed: Set<String>, usage: String) -> Result<CommandOptions, CommandOptions.UsageError> {
        do {
            let options = try CommandOptions(arguments, flags: flags)
            if let unknown = options.names.subtracting(allowed.union(flags)).sorted().first {
                return .failure(UsageError("opção desconhecida: \(unknown)\n\n\(usage)"))
            }
            if let extra = options.positional.first {
                return .failure(UsageError("argumento inesperado: \(extra)\n\n\(usage)"))
            }
            return .success(options)
        } catch {
            return .failure(UsageError("\(error)\n\n\(usage)"))
        }
    }
}
