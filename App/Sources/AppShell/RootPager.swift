import MochaClient
import MochaProtocol
import SwiftUI
import UIKit

struct RootPager: View {
    @Bindable var session: AppSession
    @State private var dragOffset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var offlineProblem: ConnectionProblem?

    private static let pageThreshold: CGFloat = 0.3
    private static let settleAnimation = Animation.smooth(duration: 0.3)

    var body: some View {
        ZStack(alignment: .top) {
            HistoryScreen(session: session, offlineMessage: offlineProblem?.message)
                .offset(x: historyOffset + dragOffset)
                .allowsHitTesting(session.rootPage == .history)
            StartScreen(session: session, offlineMessage: offlineProblem?.message)
                .offset(x: historyOffset + width + dragOffset)
                .allowsHitTesting(session.rootPage == .start)
            RootHeader(session: session, historyProgress: historyProgress, offlineMessage: offlineProblem?.message)
        }
        .onChange(of: session.connectionState, initial: true) { _, state in
            offlineProblem = HomeSections.offlineProblem(for: state, previous: offlineProblem)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(
            PagerSwipeGesture(
                page: session.rootPage,
                onChanged: changed,
                onEnded: ended
            )
        )
        .animation(Self.settleAnimation, value: session.rootPage)
    }

    private var historyProgress: CGFloat {
        let base: CGFloat = session.rootPage == .history ? 1 : 0
        guard width > 0 else { return base }
        return min(1, max(0, base + dragOffset / width))
    }

    private var historyOffset: CGFloat {
        session.rootPage == .history ? 0 : -width
    }

    private func changed(_ translation: CGFloat) {
        switch session.rootPage {
        case .start: dragOffset = min(width, max(0, translation))
        case .history: dragOffset = max(-width, min(0, translation))
        }
    }

    private func ended(_ translation: CGFloat, _ velocity: CGFloat) {
        let projected = translation + velocity * 0.2
        withAnimation(Self.settleAnimation) {
            switch session.rootPage {
            case .start where projected > width * Self.pageThreshold:
                session.showHistory()
            case .history where -projected > width * Self.pageThreshold:
                session.showStart()
            default:
                break
            }
            dragOffset = 0
        }
    }
}

private struct PagerSwipeGesture: UIGestureRecognizerRepresentable {
    let page: RootPage
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        context.coordinator.page = page
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.page = page
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended:
            onEnded(recognizer.translation(in: recognizer.view).x, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(0, 0)
        case .possible, .began:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var page: RootPage = .start

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            guard page == .start ? velocity.x > 0 : velocity.x < 0 else { return false }
            return !startsInHorizontalScroll(pan, in: view)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.delegate is HorizontalSwipeGesture.Coordinator
        }

        private func startsInHorizontalScroll(_ pan: UIPanGestureRecognizer, in view: UIView) -> Bool {
            var current = view.hitTest(pan.location(in: view), with: nil)
            while let candidate = current {
                if let scroll = candidate as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 {
                    return true
                }
                current = candidate.superview
            }
            return false
        }
    }
}
