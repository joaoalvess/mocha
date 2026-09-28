import Foundation
import MochaProtocol
import Observation

struct WebPreviewPage: Identifiable, Equatable {
    let id = UUID()
    let server: WebServer
}

@MainActor
@Observable
final class WebPreviewOpener {
    static let shared = WebPreviewOpener()

    var page: WebPreviewPage?

    static func open(_ server: WebServer) {
        shared.page = WebPreviewPage(server: server)
    }

    static func close() {
        shared.page = nil
    }
}
