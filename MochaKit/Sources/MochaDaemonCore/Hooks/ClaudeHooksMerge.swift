public enum ClaudeHooksMergeError: Error, Sendable, Equatable {
    case settingsNotAnObject
    case unexpectedShape(key: String)
}

public enum ClaudeHooksMerge {
    public struct Outcome: Sendable, Equatable {
        public var settings: OrderedJSON
        public var touchedEvents: [String]
    }

    public static func install(into settings: OrderedJSON, port: UInt16, secret: String) throws -> Outcome {
        guard settings.members != nil else { throw ClaudeHooksMergeError.settingsNotAnObject }
        let markers = ClaudeHookEntries.markers(port: port)
        var hooks = settings["hooks"] ?? .object([])
        guard hooks.members != nil else { throw ClaudeHooksMergeError.unexpectedShape(key: "hooks") }
        for event in HookEventName.allCases {
            let existing = hooks[event.rawValue] ?? .array([])
            guard let groups = existing.arrayValue else {
                throw ClaudeHooksMergeError.unexpectedShape(key: "hooks.\(event.rawValue)")
            }
            let stripped = strip(groups, markers: markers)
            var updated = stripped.groups
            updated.insert(
                ClaudeHookEntries.group(for: event, port: port, secret: secret),
                at: stripped.firstMochaIndex ?? updated.count
            )
            hooks = hooks.setting(event.rawValue, to: .array(updated))
        }
        let installed = Set(HookEventName.allCases.map(\.rawValue))
        let others = removeMochaEntries(from: hooks, markers: markers) { !installed.contains($0) }
        return Outcome(
            settings: settings.setting("hooks", to: others.hooks),
            touchedEvents: HookEventName.allCases.map(\.rawValue)
        )
    }

    public static func uninstall(from settings: OrderedJSON, port: UInt16) throws -> Outcome {
        guard settings.members != nil else { throw ClaudeHooksMergeError.settingsNotAnObject }
        guard let hooks = settings["hooks"], hooks.members != nil else {
            return Outcome(settings: settings, touchedEvents: [])
        }
        let removal = removeMochaEntries(from: hooks, markers: ClaudeHookEntries.markers(port: port)) { _ in true }
        guard !removal.events.isEmpty else { return Outcome(settings: settings, touchedEvents: []) }
        let emptied = removal.hooks.members?.isEmpty ?? false
        return Outcome(settings: settings.setting("hooks", to: emptied ? nil : removal.hooks), touchedEvents: removal.events)
    }

    private static func removeMochaEntries(
        from hooks: OrderedJSON,
        markers: Set<String>,
        where includes: (String) -> Bool
    ) -> (hooks: OrderedJSON, events: [String]) {
        var result = hooks
        var events: [String] = []
        for member in hooks.members ?? [] where includes(member.key) {
            guard let groups = member.value.arrayValue else { continue }
            let stripped = strip(groups, markers: markers)
            guard stripped.firstMochaIndex != nil else { continue }
            events.append(member.key)
            result = result.setting(member.key, to: stripped.groups.isEmpty ? nil : .array(stripped.groups))
        }
        return (result, events)
    }

    private static func strip(_ groups: [OrderedJSON], markers: Set<String>) -> (groups: [OrderedJSON], firstMochaIndex: Int?) {
        var kept: [OrderedJSON] = []
        var firstMochaIndex: Int?
        for group in groups {
            guard let hooks = group["hooks"]?.arrayValue else {
                kept.append(group)
                continue
            }
            let remaining = hooks.filter { !ClaudeHookEntries.isMocha($0, markers: markers) }
            guard remaining.count != hooks.count else {
                kept.append(group)
                continue
            }
            if firstMochaIndex == nil {
                firstMochaIndex = kept.count
            }
            if !remaining.isEmpty {
                kept.append(group.setting("hooks", to: .array(remaining)))
            }
        }
        return (kept, firstMochaIndex)
    }
}
