import MochaProtocol

enum DemoControls {
    static let defaultEffort = EffortLevel.xhigh.rawValue
    static let noEffortMessage = "Este modelo não tem effort."
    static let modeUnavailableMessage = "Modo indisponível neste modelo"

    static func modelId(for alias: ModelAlias) -> String {
        switch alias {
        case .fable: "claude-fable-5"
        case .opus: "claude-opus-5-5"
        case .sonnet: "claude-sonnet-5"
        case .haiku: "claude-haiku-4-5-20251001"
        }
    }

    static func hasEffort(model: String?) -> Bool {
        !(model?.contains(ModelAlias.haiku.rawValue) ?? false)
    }
}
