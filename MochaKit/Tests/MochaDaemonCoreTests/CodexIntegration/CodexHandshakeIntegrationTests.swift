import Foundation
import Testing
@testable import MochaDaemonCore

@Suite(.tags(.integration), .enabled(if: CodexLab.isEnabled), .timeLimit(.minutes(1)))
struct CodexHandshakeIntegrationTests {
    @Test func initializeAnswersFromTheLabCodexHome() async throws {
        let lab = try #require(CodexLab.current)
        let result = try await lab.withServer { _, initialize in initialize }
        let home = result["codexHome"]?.stringValue.map(CodexLab.standardized)
        #expect(home == lab.codexHome, "o App Server do lab não usa o CODEX_HOME do lab: \(result.compactSerialized())")
        #expect(CodexInspector.version(fromUserAgent: result["userAgent"]?.stringValue) == lab.version, "initialize real: \(result.compactSerialized())")
        #expect(result["platformFamily"]?.stringValue != nil, "initialize real: \(result.compactSerialized())")
    }

    @Test func experimentalApiUnlocksTheCollaborationModes() async throws {
        let lab = try #require(CodexLab.current)
        let modes = try await lab.withServer { server, _ in
            try await server.request("collaborationMode/list", params: .object([]))
        }
        let names = Set(modes["data"]?.arrayValue?.compactMap { $0["mode"]?.stringValue } ?? [])
        #expect(names.isSuperset(of: ["plan", "default"]), "collaborationMode/list real: \(modes.compactSerialized())")
    }

    @Test func doctorProbeSeesASignedInAppServer() async throws {
        let lab = try #require(CodexLab.current)
        let probe = await CodexInspector.appServer(at: lab.socketPath, timeout: .seconds(10))
        guard case .reachable(let info) = probe else {
            Issue.record("doctor real: \(probe)")
            return
        }
        #expect(info.version == lab.version)
        #expect(info.signedIn == true, "sem login no lab: rode CODEX_HOME=\(lab.codexHome) codex login")
        #expect(info.plan != nil)
    }

    @Test func modelListOffersVisibleModelsWithTheirEfforts() async throws {
        let lab = try #require(CodexLab.current)
        let list = try await lab.withServer { server, _ in
            try await server.request("model/list", params: .object([]))
        }
        let visible = (list["data"]?.arrayValue ?? []).filter { $0["hidden"]?.boolValue != true }
        #expect(!visible.isEmpty, "model/list real: \(list.compactSerialized())")
        #expect(visible.contains { $0["isDefault"]?.boolValue == true }, "model/list real: \(list.compactSerialized())")
        for model in visible {
            let efforts = model["supportedReasoningEfforts"]?.arrayValue?.compactMap { $0["reasoningEffort"]?.stringValue } ?? []
            let fallback = model["defaultReasoningEffort"]?.stringValue
            #expect(model["model"]?.stringValue != nil && model["displayName"]?.stringValue != nil, "modelo real: \(model.compactSerialized())")
            #expect(!efforts.isEmpty && fallback.map(efforts.contains) == true, "modelo real: \(model.compactSerialized())")
        }
    }
}
