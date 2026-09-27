import MochaProtocol

enum PendingRequestFactory {
    static let questionToolName = "AskUserQuestion"
    static let inputJSONLimit = 4_000

    static func kind(for request: PermissionRequestHook) -> PendingKind {
        guard request.toolName != questionToolName else {
            return .question(questions: questions(in: request.toolInput))
        }
        return .permission(
            toolName: request.toolName,
            summary: PushAlertText.summary(toolName: request.toolName, input: request.toolInput, cwd: request.context.cwd),
            inputJSON: String(request.toolInput.compactSerialized().prefix(inputJSONLimit))
        )
    }

    static func questions(in toolInput: OrderedJSON) -> [PendingQuestion] {
        (toolInput["questions"]?.arrayValue ?? []).compactMap { entry in
            guard let question = entry["question"]?.stringValue else { return nil }
            let options = (entry["options"]?.arrayValue ?? []).compactMap { option -> PendingOption? in
                guard let label = option["label"]?.stringValue else { return nil }
                return PendingOption(label: label, description: option["description"]?.stringValue)
            }
            return PendingQuestion(
                header: entry["header"]?.stringValue ?? "",
                question: question,
                options: options,
                multiSelect: entry["multiSelect"]?.boolValue ?? false
            )
        }
    }
}
