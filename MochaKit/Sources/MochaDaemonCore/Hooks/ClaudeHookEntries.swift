enum ClaudeHookEntries {
    static let commandTimeout = 5
    static let permissionRequestTimeout = 590
    static let paneEnvironmentVariable = "HERDR_PANE_ID"

    static func url(for event: HookEventName, port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(event.path)"
    }

    static func command(for event: HookEventName, port: UInt16, secret: String) -> String {
        "/usr/bin/curl -s -m 3 -o /dev/null -X POST -H 'Content-Type: application/json' "
            + "-H \"\(HookServer.paneHeader): $\(paneEnvironmentVariable)\" "
            + "-H '\(HookServer.secretHeader): \(secret)' "
            + "--data-binary @- \(url(for: event, port: port)) || true"
    }

    static func group(for event: HookEventName, port: UInt16, secret: String) -> OrderedJSON {
        .object([OrderedJSON.Member("hooks", .array([hook(for: event, port: port, secret: secret)]))])
    }

    static func hook(for event: HookEventName, port: UInt16, secret: String) -> OrderedJSON {
        guard event.usesHttpHook else {
            return .object([
                OrderedJSON.Member("type", .string("command")),
                OrderedJSON.Member("async", .bool(true)),
                OrderedJSON.Member("timeout", .number(String(commandTimeout))),
                OrderedJSON.Member("command", .string(command(for: event, port: port, secret: secret))),
            ])
        }
        return .object([
            OrderedJSON.Member("type", .string("http")),
            OrderedJSON.Member("url", .string(url(for: event, port: port))),
            OrderedJSON.Member("headers", .object([
                OrderedJSON.Member(HookServer.paneHeader, .string("$" + paneEnvironmentVariable)),
                OrderedJSON.Member(HookServer.secretHeader, .string(secret)),
            ])),
            OrderedJSON.Member("allowedEnvVars", .array([.string(paneEnvironmentVariable)])),
            OrderedJSON.Member("timeout", .number(String(permissionRequestTimeout))),
        ])
    }

    static func markers(port: UInt16) -> Set<String> {
        [ClaudeSettingsInspector.mochaMarker, "127.0.0.1:\(port)\(HookEventName.pathPrefix)"]
    }

    static func isMocha(_ hook: OrderedJSON, markers: Set<String>) -> Bool {
        [hook["command"]?.stringValue, hook["url"]?.stringValue]
            .compactMap { $0 }
            .contains { target in markers.contains { target.contains($0) } }
    }

    static func isSafeSecret(_ secret: String) -> Bool {
        !secret.isEmpty && secret.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-" || scalar == "_"
        }
    }
}
