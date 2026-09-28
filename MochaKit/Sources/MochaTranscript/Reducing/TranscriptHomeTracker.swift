import Foundation
import MochaProtocol

struct ScannedActivity: Sendable, Equatable {
    let itemId: String
    let call: ToolCall
}

struct TranscriptHomeTracker {
    private var runningIds: [String] = []
    private var runningCalls: [String: ToolCall] = [:]
    private var knownToolItems: Set<String> = []
    private var lastCall: ToolCall?
    private var lastCallId: String?
    private var lastMessage: ChatItem?
    private var computedPreview: (item: ChatItem, preview: MessagePreview?)?
    private var lastPrompt: ChatItem?
    private var computedPrompt: (item: ChatItem, text: String?)?
    private var olderRunning: ToolCall?
    private var olderLast: ToolCall?

    mutating func absorb(_ changes: [TranscriptChange]) {
        for change in changes {
            let item = change.item
            switch item.kind {
            case .toolCall(let call):
                absorbToolCall(call, id: item.id, isAppend: change.isAppend)
            case .userPrompt:
                if change.isAppend {
                    lastMessage = item
                    lastPrompt = item
                }
            case .assistantText:
                if change.isAppend {
                    lastMessage = item
                }
            default:
                break
            }
        }
    }

    mutating func seed(olderActivity scanned: ScannedActivity?) {
        guard let scanned else { return }
        if scanned.call.status == .running {
            if !knownToolItems.contains(scanned.itemId) {
                olderRunning = scanned.call
            }
        } else {
            olderLast = scanned.call
        }
    }

    mutating func apply(to header: inout TranscriptHeader) {
        if let lastMessage {
            if computedPreview?.item != lastMessage {
                computedPreview = (lastMessage, MessagePreview(transcriptItem: lastMessage))
            }
            header.preview = computedPreview?.preview
        }
        if let lastPrompt {
            if computedPrompt?.item != lastPrompt {
                computedPrompt = (lastPrompt, MessagePreview(transcriptItem: lastPrompt)?.text)
            }
            header.prompt = computedPrompt?.text
        }
        if let call = currentActivityCall {
            header.activity = ToolActivity(call: call)
        }
    }

    private var currentActivityCall: ToolCall? {
        if let id = runningIds.last, let call = runningCalls[id] {
            return call
        }
        return olderRunning ?? lastCall ?? olderLast
    }

    private mutating func absorbToolCall(_ call: ToolCall, id: String, isAppend: Bool) {
        knownToolItems.insert(id)
        if isAppend {
            if call.status == .running {
                runningIds.append(id)
                runningCalls[id] = call
            }
            lastCall = call
            lastCallId = id
            return
        }
        if call.status == .running {
            if runningCalls[id] != nil {
                runningCalls[id] = call
            }
        } else if runningCalls.removeValue(forKey: id) != nil, let position = runningIds.lastIndex(of: id) {
            runningIds.remove(at: position)
        }
        if lastCallId == id {
            lastCall = call
        }
    }
}

extension TranscriptChange {
    var isAppend: Bool {
        if case .append = self { return true }
        return false
    }
}

extension ToolActivity {
    init(call: ToolCall) {
        self.init(toolName: call.name, summary: call.summary, status: call.status)
    }
}

extension MessagePreview {
    static let imageOnlyText = "[imagem]"

    static func withoutPastedContentTags(_ text: String) -> String {
        text.replacing(/<\/?pasted_content\b[^>]*>/, with: " ")
    }

    init?(transcriptItem item: ChatItem) {
        switch item.kind {
        case .userPrompt(let text, let imageCount):
            let plain = PlainText.preview(fromMarkdown: Self.withoutPastedContentTags(text))
            self.init(author: .user, text: plain.isEmpty && imageCount > 0 ? Self.imageOnlyText : plain)
        case .assistantText(let markdown):
            self.init(author: .assistant, text: PlainText.preview(fromMarkdown: markdown))
        default:
            return nil
        }
    }
}
