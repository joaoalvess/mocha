import AppIntents
import MochaClient

struct AllowPendingRequestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Permitir"
    static let isDiscoverable = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Pedido") var requestId: String
    @Parameter(title: "Agente") var agentId: String

    init() {}

    init(requestId: String, agentId: String) {
        self.requestId = requestId
        self.agentId = agentId
    }

    func perform() async throws -> some IntentResult {
        #if !MOCHA_WIDGETS
        await PendingActivityResponder.respond(.allow, requestId: requestId, agentId: agentId)
        #endif
        return .result()
    }
}

struct DenyPendingRequestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Negar"
    static let isDiscoverable = false

    @Parameter(title: "Pedido") var requestId: String
    @Parameter(title: "Agente") var agentId: String

    init() {}

    init(requestId: String, agentId: String) {
        self.requestId = requestId
        self.agentId = agentId
    }

    func perform() async throws -> some IntentResult {
        #if !MOCHA_WIDGETS
        await PendingActivityResponder.respond(.deny, requestId: requestId, agentId: agentId)
        #endif
        return .result()
    }
}

struct AnswerPendingQuestionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Responder"
    static let isDiscoverable = false

    @Parameter(title: "Pedido") var requestId: String
    @Parameter(title: "Agente") var agentId: String
    @Parameter(title: "Pergunta") var question: String
    @Parameter(title: "Opção") var label: String

    init() {}

    init(requestId: String, agentId: String, question: String, label: String) {
        self.requestId = requestId
        self.agentId = agentId
        self.question = question
        self.label = label
    }

    func perform() async throws -> some IntentResult {
        #if !MOCHA_WIDGETS
        await PendingActivityResponder.respond(.answer(question: question, label: label), requestId: requestId, agentId: agentId)
        #endif
        return .result()
    }
}
