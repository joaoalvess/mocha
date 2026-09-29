import Foundation

public struct FakeClaudeScreen: Sendable, Equatable {
    public enum Overlay: Sendable, Equatable {
        case none
        case modelPicker(cursor: Int)
        case effortPicker(cursor: Int)
        case switchDialog
    }

    public struct ModelRow: Sendable, Equatable {
        public var name: String
        public var displayName: String
        public var detail: String

        public init(name: String, displayName: String, detail: String) {
            self.name = name
            self.displayName = displayName
            self.detail = detail
        }
    }

    public static let footers: [String: String] = [
        "default": "  ⏸ manual mode on · ? for shortcuts · ← for agents",
        "acceptEdits": "  ⏵⏵ accept edits on (shift+tab to cycle) · ← for agents",
        "plan": "  ⏸ plan mode on (shift+tab to cycle) · ← for agents",
        "auto": "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents",
    ]

    public static let sonnetCycle = ["default", "acceptEdits", "plan", "auto"]
    public static let haikuCycle = ["default", "acceptEdits", "plan"]
    public static let effortLevels = ["low", "medium", "high", "xhigh", "max"]

    public static let modelRows = [
        ModelRow(name: "Default (recommended)", displayName: "Opus 5.5", detail: "Opus 5.5 · Most capable for complex work"),
        ModelRow(name: "Opus", displayName: "Opus 5.5", detail: "Opus 5.5 · Most capable for complex work"),
        ModelRow(name: "Fable", displayName: "Fable 5.1", detail: "Fable 5.1 · Creative and conversational"),
        ModelRow(name: "Sonnet", displayName: "Sonnet 5.5", detail: "Sonnet 5.5 · Best for everyday tasks"),
        ModelRow(name: "Haiku", displayName: "Haiku 4.5", detail: "Haiku 4.5 · Fastest for quick answers"),
    ]

    public static let switchDialogText = """
          Switch model?
          Your next response will be slower and use more tokens

          ❯ 1. Yes, switch to Sonnet 5.5
            2. No, go back
        """

    public var modes: [String]
    public var modeIndex: Int
    public var modelIndex: Int
    public var effortIndex: Int
    public var overlay: Overlay
    public var history: [String]
    public var fixedText: String?
    public var opensPickers = true
    public var confirmsPickers = true
    public var movesCursor = true
    public var cyclesMode = true

    public init(
        modes: [String] = FakeClaudeScreen.sonnetCycle,
        mode: String = "default",
        model: String = "Sonnet",
        effort: String = "high",
        overlay: Overlay = .none,
        history: [String] = ["⏺ pronto"]
    ) {
        self.modes = modes
        modeIndex = modes.firstIndex(of: mode) ?? 0
        modelIndex = Self.modelRows.firstIndex { $0.name == model } ?? 3
        effortIndex = Self.effortLevels.firstIndex(of: effort) ?? 2
        self.overlay = overlay
        self.history = history
    }

    public static func fixed(_ text: String) -> FakeClaudeScreen {
        var screen = FakeClaudeScreen()
        screen.fixedText = text
        return screen
    }

    public var mode: String {
        modes[modeIndex]
    }

    public var model: String {
        Self.modelRows[modelIndex].name
    }

    public var effort: String {
        Self.effortLevels[effortIndex]
    }

    public var text: String {
        if let fixedText {
            return fixedText
        }
        var lines = history
        switch overlay {
        case .none:
            lines += [Self.rule, "❯ ", Self.rule, Self.footers[mode] ?? ""]
        case .modelPicker(let cursor):
            lines += [
                Self.rule,
                "  Select model",
                "  Switch between Claude models. Your pick becomes the default for new sessions.",
                "",
            ]
            for (index, row) in Self.modelRows.enumerated() {
                let marker = index == cursor ? "❯" : " "
                let check = index == modelIndex ? " ✔" : ""
                let label = "\(index + 1). \(row.name)\(check)"
                lines.append("  \(marker) \(label.padding(toLength: 26, withPad: " ", startingAt: 0))\(row.detail)")
            }
            lines += [
                "",
                "  ● High effort ←/→ to adjust",
                "",
                "  Enter to set as default · s to use this session only · Esc to cancel",
            ]
        case .effortPicker(let cursor):
            let indent = String(repeating: " ", count: 35)
            let labels = Self.effortLevels.map { $0.padding(toLength: 10, withPad: " ", startingAt: 0) }.joined()
            let center = 35 + cursor * 10 + Self.effortLevels[cursor].count / 2
            let slider = String(repeating: "─", count: center - 35) + "▲" + String(repeating: "─", count: 76 - center)
            lines += [
                Self.rule,
                "  Effort",
                "",
                "\(indent)Faster                             Smarter",
                "\(indent)\(slider)      Ultracode  off",
                "\(indent)\(labels)Tab to toggle",
                "",
                "",
                "  ←/→ to adjust · Enter to confirm · s for this session only · Esc to cancel",
            ]
        case .switchDialog:
            lines += [Self.rule] + Self.switchDialogText.components(separatedBy: "\n")
        }
        return lines.joined(separator: "\n")
    }

    public mutating func prompt(_ text: String) {
        guard fixedText == nil else { return }
        switch text {
        case "/model" where opensPickers:
            overlay = .modelPicker(cursor: modelIndex)
        case "/effort" where opensPickers:
            overlay = .effortPicker(cursor: effortIndex)
        default:
            history.append("❯ \(text)")
        }
    }

    public mutating func press(_ key: String) {
        guard fixedText == nil else { return }
        switch (overlay, key.lowercased()) {
        case (.none, "shift+tab") where cyclesMode:
            modeIndex = (modeIndex + 1) % modes.count
        case (.modelPicker(let cursor), "up") where movesCursor:
            overlay = .modelPicker(cursor: max(0, cursor - 1))
        case (.modelPicker(let cursor), "down") where movesCursor:
            overlay = .modelPicker(cursor: min(Self.modelRows.count - 1, cursor + 1))
        case (.modelPicker(let cursor), "s") where confirmsPickers:
            modelIndex = cursor
            overlay = .none
            history += ["❯ /model", "  ⎿  Set model to \(Self.modelRows[cursor].displayName) for this session only"]
        case (.effortPicker(let cursor), "left") where movesCursor:
            overlay = .effortPicker(cursor: max(0, cursor - 1))
        case (.effortPicker(let cursor), "right") where movesCursor:
            overlay = .effortPicker(cursor: min(Self.effortLevels.count - 1, cursor + 1))
        case (.effortPicker(let cursor), "s") where confirmsPickers:
            effortIndex = cursor
            overlay = .none
            history += ["❯ /effort", "  ⎿  Set effort level to \(Self.effortLevels[cursor]) (this session only)"]
        case (.modelPicker, "escape"), (.modelPicker, "esc"), (.effortPicker, "escape"), (.effortPicker, "esc"), (.switchDialog, "escape"),
            (.switchDialog, "esc"):
            overlay = .none
        default:
            break
        }
    }

    private static let rule = "──────────────────────────────────────────────"
}
