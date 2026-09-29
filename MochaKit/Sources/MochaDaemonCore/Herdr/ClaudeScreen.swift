import Foundation
import MochaProtocol

enum ClaudeScreen {
    static let selectorErrorCode = "selector"
    static let modeKey = "shift+tab"
    static let confirmKey = "s"
    static let escapeKey = "Escape"
    static let busyScanLines = 8

    static let modeFooters: [(prefix: String, mode: String)] = [
        ("⏸ manual mode on", "default"),
        ("⏵⏵ accept edits on", "acceptEdits"),
        ("⏸ plan mode on", "plan"),
        ("⏵⏵ auto mode on", "auto"),
    ]

    static let modelPickerMarker = "s to use this session only"
    static let effortPickerMarker = "s for this session only"
    static let switchDialogMarker = "Switch model?"
    static let modelPickerTitle = "Select model"

    struct ModelPicker: Equatable {
        var rows: [String]
        var cursor: Int
    }

    struct EffortPicker: Equatable {
        var levels: [String]
        var cursor: Int
    }

    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    static func lastLine(_ text: String) -> String {
        lines(text).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
    }

    static func mode(fromFooter line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return modeFooters.first { trimmed.hasPrefix($0.prefix) }?.mode
    }

    static func isBusy(_ text: String) -> Bool {
        guard mode(fromFooter: lastLine(text)) == nil else { return false }
        let bottom = lines(text).suffix(busyScanLines)
        return bottom.contains { line in
            line.contains(modelPickerMarker) || line.contains(effortPickerMarker) || line.contains(switchDialogMarker)
        }
    }

    static func modelPicker(_ text: String) -> ModelPicker? {
        guard text.contains(modelPickerMarker) else { return nil }
        let all = lines(text)
        let start = all.lastIndex { $0.contains(modelPickerTitle) } ?? all.startIndex
        var rows: [String] = []
        var cursor: Int?
        for line in all[start...] {
            var rest = Substring(line.trimmingCharacters(in: .whitespaces))
            let isCursor = rest.hasPrefix("❯")
            if isCursor {
                rest = rest.dropFirst().drop { $0 == " " }
            }
            guard let dot = rest.firstIndex(of: "."), let number = Int(rest[rest.startIndex..<dot]), number == rows.count + 1 else { continue }
            let name = rest[rest.index(after: dot)...].drop { $0 == " " }.prefix { $0 != " " }
            guard !name.isEmpty else { continue }
            if isCursor {
                cursor = rows.count
            }
            rows.append(String(name))
        }
        guard let cursor, !rows.isEmpty else { return nil }
        return ModelPicker(rows: rows, cursor: cursor)
    }

    static func row(for model: ModelAlias, in picker: ModelPicker) -> Int? {
        picker.rows.firstIndex { $0.lowercased() == model.rawValue }
    }

    static func effortPicker(_ text: String) -> EffortPicker? {
        guard text.contains(effortPickerMarker) else { return nil }
        let known = Set(EffortLevel.allCases.map(\.rawValue))
        let all = lines(text)
        for (index, line) in all.enumerated().dropFirst() {
            let words = columnWords(line)
            guard let first = words.first, known.contains(first.word) else { continue }
            let labels = words.filter { known.contains($0.word) }
            guard let marker = Array(all[index - 1]).firstIndex(of: "▲"),
                  let cursor = labels.indices.min(by: { abs(labels[$0].center - Double(marker)) < abs(labels[$1].center - Double(marker)) })
            else { return nil }
            return EffortPicker(levels: labels.map(\.word), cursor: cursor)
        }
        return nil
    }

    private static func columnWords(_ line: String) -> [(word: String, center: Double)] {
        var words: [(word: String, center: Double)] = []
        var current = ""
        for (column, character) in Array(line + " ").enumerated() {
            if character == " " {
                if !current.isEmpty {
                    words.append((current, Double(column - current.count) + Double(current.count - 1) / 2))
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        return words
    }

    static func modelConfirmations(_ text: String) -> [String] {
        lines(text).compactMap { line in
            guard let start = line.range(of: "Set model to "), let end = line.range(of: " for this session only", range: start.upperBound..<line.endIndex) else {
                return nil
            }
            return String(line[start.upperBound..<end.lowerBound])
        }
    }

    static func effortConfirmations(_ text: String) -> [String] {
        lines(text).compactMap { line in
            guard let start = line.range(of: "Set effort level to "), let end = line.range(of: " (this session only)", range: start.upperBound..<line.endIndex) else {
                return nil
            }
            return String(line[start.upperBound..<end.lowerBound])
        }
    }

    static func moves(from current: Int, to target: Int, back: String, forward: String) -> [String] {
        target >= current ? Array(repeating: forward, count: target - current) : Array(repeating: back, count: current - target)
    }
}
