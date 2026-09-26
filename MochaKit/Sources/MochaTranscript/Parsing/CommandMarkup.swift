import Foundation

enum CommandMarkup {
    static func innerText(of tag: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(tag)>") else { return nil }
        let rest = text[open.upperBound...]
        guard let close = rest.range(of: "</\(tag)>") else { return String(rest) }
        return String(rest[..<close.lowerBound])
    }

    static func slashCommand(in text: String) -> (name: String, args: String)? {
        guard let name = innerText(of: "command-name", in: text)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let args = innerText(of: "command-args", in: text)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (name, args)
    }

    static func localCommandOutput(in text: String) -> String {
        joinedOutput(stdout: innerText(of: "local-command-stdout", in: text), stderr: innerText(of: "local-command-stderr", in: text))
    }

    static func bashOutput(in text: String) -> String {
        joinedOutput(stdout: innerText(of: "bash-stdout", in: text), stderr: innerText(of: "bash-stderr", in: text))
    }

    static func taskNotificationSummary(in text: String) -> String {
        if let summary = innerText(of: "summary", in: text)?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanOutput(_ text: String) -> String {
        strippingANSI(text).trimmingNewlines()
    }

    private static func joinedOutput(stdout: String?, stderr: String?) -> String {
        [stdout, stderr]
            .compactMap { $0.map(cleanOutput) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func strippingANSI(_ text: String) -> String {
        guard text.unicodeScalars.contains("\u{1B}") else { return text }
        var output = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        var pending = scalars.next()
        while let scalar = pending {
            pending = scalars.next()
            guard scalar == "\u{1B}" else {
                output.append(scalar)
                continue
            }
            guard let introducer = pending else { break }
            pending = scalars.next()
            switch introducer {
            case "[":
                while let next = pending {
                    pending = scalars.next()
                    if (0x40...0x7E).contains(next.value) { break }
                }
            case "]":
                while let next = pending {
                    pending = scalars.next()
                    if next == "\u{07}" { break }
                    if next == "\u{1B}" {
                        if pending == "\\" { pending = scalars.next() }
                        break
                    }
                }
            default:
                break
            }
        }
        return String(output)
    }
}
