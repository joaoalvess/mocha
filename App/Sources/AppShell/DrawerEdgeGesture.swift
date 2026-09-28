import SwiftUI
import UIKit

struct DrawerEdgeGesture: UIGestureRecognizerRepresentable {
    let onOpen: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        if recognizer.state == .began {
            onOpen()
        }
    }
}
