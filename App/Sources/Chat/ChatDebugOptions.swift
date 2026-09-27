#if DEBUG
import SwiftUI

struct ChatDebugOptions {
    var openSessionId: String?
    var openSubagentId: String?
    var scrollToItemId: String?
    var scrollAnchor: UnitPoint = .top
    var expandToolItemId: String?
    var focusComposer = false
    var draft: String?
    var sendText: String?
    var attachSampleCount: Int?
    var opensAttachMenu = false
    var opensSlashMenu = false
    var confirmsClear = false
    var slashCommand: String?
    var closeChatAfter: Duration?
    var olderPageDelay: Duration?
    var performanceSweep = false

    static let openSessionKey = "chat-open-session"
    static let openSubagentKey = "chat-open-subagent"
    static let scrollToKey = "chat-scroll-to"
    static let scrollAnchorKey = "chat-scroll-anchor"
    static let expandToolKey = "chat-expand-tool"
    static let focusComposerKey = "chat-focus-composer"
    static let draftKey = "chat-draft"
    static let sendKey = "chat-send"
    static let attachSamplesKey = "chat-attach-samples"
    static let attachMenuKey = "chat-attach-menu"
    static let slashMenuKey = "chat-slash-menu"
    static let confirmClearKey = "chat-confirm-clear"
    static let slashCommandKey = "chat-slash"
    static let closeChatAfterKey = "chat-close-after"
    static let olderPageDelayKey = "chat-older-delay"
    static let performanceSweepKey = "chat-perf-sweep"

    static func current(argumentDomain: [String: Any] = LaunchArguments.argumentDomain()) -> ChatDebugOptions {
        var options = ChatDebugOptions()
        options.openSessionId = argumentDomain[openSessionKey] as? String
        options.openSubagentId = argumentDomain[openSubagentKey] as? String
        options.scrollToItemId = argumentDomain[scrollToKey] as? String
        options.scrollAnchor = anchor(argumentDomain[scrollAnchorKey])
        options.expandToolItemId = argumentDomain[expandToolKey] as? String
        options.focusComposer = flag(argumentDomain[focusComposerKey])
        options.draft = argumentDomain[draftKey] as? String
        options.sendText = argumentDomain[sendKey] as? String
        options.attachSampleCount = (argumentDomain[attachSamplesKey] as? String).flatMap(Int.init)
        options.opensAttachMenu = flag(argumentDomain[attachMenuKey])
        options.opensSlashMenu = flag(argumentDomain[slashMenuKey])
        options.confirmsClear = flag(argumentDomain[confirmClearKey])
        options.slashCommand = argumentDomain[slashCommandKey] as? String
        options.closeChatAfter = (argumentDomain[closeChatAfterKey] as? String).flatMap(Double.init).map { .milliseconds(Int($0 * 1_000)) }
        options.olderPageDelay = (argumentDomain[olderPageDelayKey] as? String).flatMap(Double.init).map { .milliseconds(Int($0 * 1_000)) }
        options.performanceSweep = flag(argumentDomain[performanceSweepKey])
        return options
    }

    private static func anchor(_ value: Any?) -> UnitPoint {
        switch value as? String {
        case "center": .center
        case "bottom": .bottom
        default: .top
        }
    }

    private static func flag(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return ["yes", "true", "1"].contains(text.lowercased())
    }
}

@MainActor
enum ChatDebugLaunch {
    private static var consumed: Set<String> = []

    static func consume(_ key: String) -> Bool {
        consumed.insert(key).inserted
    }
}
#endif
