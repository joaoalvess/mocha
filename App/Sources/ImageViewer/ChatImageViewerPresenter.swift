import CoreGraphics
import CoreTransferable
import MochaClient
import Observation
import UniformTypeIdentifiers

struct ChatImageSelection: Identifiable, Hashable {
    let path: String

    var id: String { path }
}

@MainActor
@Observable
final class ChatImageViewerPresenter {
    var selection: ChatImageSelection?

    func open(_ path: String) {
        selection = ChatImageSelection(path: path)
    }

    func close() {
        selection = nil
    }
}

struct ShareableImage: Transferable {
    let image: CGImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { shareable in
            try ImageReduction.jpeg(shareable.image)
        }
    }
}
