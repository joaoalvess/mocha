import MochaProtocol

public enum PendingRespondError: Error, Sendable, Equatable {
    case requestNotFound
    case invalidPayload(String)
}

enum PendingHookReply {
    static let defaultDenyMessage = "Negado pelo usuário no iPhone."
    static let allowOnQuestion = "Uma pergunta se responde com answers ou deny."
    static let answersOnPermission = "Uma permissão se responde com allow ou deny."
    static let multipleAnswerSeparator = ", "
    static let planApprovedMode = "auto"

    static let noDecision = OrderedJSON.object([])

    static func reply(to response: PendingResponse, kind: PendingKind, toolInput: OrderedJSON) throws(PendingRespondError) -> OrderedJSON {
        switch (response, kind) {
        case (.allow, .permission(let toolName, _, _)) where toolName == PendingRequestFactory.planToolName:
            return planAllow(toolInput: toolInput)
        case (.allow, .permission):
            return allow()
        case (.allow, .question):
            throw .invalidPayload(allowOnQuestion)
        case (.deny(let reason), _):
            return deny(reason)
        case (.answers, .permission):
            throw .invalidPayload(answersOnPermission)
        case (.answers(let chosen), .question(let questions)):
            return answers(try answerMembers(chosen, questions: questions), questions: toolInput["questions"] ?? .array([]))
        }
    }

    static func allow() -> OrderedJSON {
        decision([OrderedJSON.Member("behavior", .string("allow"))])
    }

    static func planAllow(toolInput: OrderedJSON) -> OrderedJSON {
        decision([
            OrderedJSON.Member("behavior", .string("allow")),
            OrderedJSON.Member("updatedInput", toolInput),
            OrderedJSON.Member("updatedPermissions", .array([
                .object([
                    OrderedJSON.Member("type", .string("setMode")),
                    OrderedJSON.Member("mode", .string(planApprovedMode)),
                    OrderedJSON.Member("destination", .string("session")),
                ]),
            ])),
        ])
    }

    static func deny(_ reason: String?) -> OrderedJSON {
        let message = reason.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 } ?? defaultDenyMessage
        return decision([
            OrderedJSON.Member("behavior", .string("deny")),
            OrderedJSON.Member("message", .string(message)),
        ])
    }

    static func answers(_ answers: [OrderedJSON.Member], questions: OrderedJSON) -> OrderedJSON {
        decision([
            OrderedJSON.Member("behavior", .string("allow")),
            OrderedJSON.Member("updatedInput", .object([
                OrderedJSON.Member("questions", questions),
                OrderedJSON.Member("answers", .object(answers)),
            ])),
        ])
    }

    static func answerText(_ chosen: [String], for question: PendingQuestion) -> String? {
        var seen: Set<String> = []
        let values = chosen.filter { !$0.allSatisfy(\.isWhitespace) && seen.insert($0).inserted }
        guard !values.isEmpty else { return nil }
        var ordered: [String] = []
        for label in question.options.map(\.label) where values.contains(label) && !ordered.contains(label) {
            ordered.append(label)
        }
        let freeText = values.filter { !ordered.contains($0) }
        return (ordered + freeText).joined(separator: multipleAnswerSeparator)
    }

    static func missingAnswer(_ question: String) -> String {
        "Toda pergunta precisa de resposta: falta \"\(question)\"."
    }

    private static func answerMembers(_ chosen: [String: [String]], questions: [PendingQuestion]) throws(PendingRespondError) -> [OrderedJSON.Member] {
        var members: [OrderedJSON.Member] = []
        for question in questions where !members.contains(where: { $0.key == question.question }) {
            guard let text = answerText(chosen[question.question] ?? [], for: question) else {
                throw .invalidPayload(missingAnswer(question.question))
            }
            members.append(OrderedJSON.Member(question.question, .string(text)))
        }
        return members
    }

    private static func decision(_ members: [OrderedJSON.Member]) -> OrderedJSON {
        .object([
            OrderedJSON.Member("hookSpecificOutput", .object([
                OrderedJSON.Member("hookEventName", .string(HookEventName.permissionRequest.rawValue)),
                OrderedJSON.Member("decision", .object(members)),
            ])),
        ])
    }
}
