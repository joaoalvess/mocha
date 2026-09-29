import SwiftUI
import UIKit

struct FloatingMenuLayer<Content: View>: UIViewRepresentable {
    let content: Content

    func makeCoordinator() -> FloatingMenuLayerCoordinator<Content> {
        FloatingMenuLayerCoordinator()
    }

    func makeUIView(context: Context) -> FloatingMenuAnchorView {
        let view = FloatingMenuAnchorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: FloatingMenuAnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.content = content
        uiView.onWindowChange = { [weak coordinator] scene in coordinator?.attach(to: scene) }
        coordinator.attach(to: uiView.window?.windowScene)
    }

    static func dismantleUIView(_ uiView: FloatingMenuAnchorView, coordinator: FloatingMenuLayerCoordinator<Content>) {
        uiView.onWindowChange = nil
        coordinator.tearDown()
    }
}

final class FloatingMenuAnchorView: UIView {
    var onWindowChange: ((UIWindowScene?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window?.windowScene)
    }
}

@MainActor
final class FloatingMenuLayerCoordinator<Content: View> {
    var content: Content?
    private var window: FloatingMenuWindow?
    private var host: UIHostingController<FloatingMenuRoot<Content>>?

    private static var windowLevel: UIWindow.Level { .normal + 1 }

    func attach(to scene: UIWindowScene?) {
        guard let content else { return }
        if let host {
            host.rootView = root(content)
            return
        }
        guard let scene else { return }
        let window = FloatingMenuWindow(windowScene: scene)
        let host = UIHostingController(rootView: root(content))
        host.view.backgroundColor = .clear
                window.windowLevel = Self.windowLevel
        window.backgroundColor = .clear
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        self.host = host
        self.window = window
    }

    func tearDown() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        host = nil
        content = nil
    }

    private func root(_ content: Content) -> FloatingMenuRoot<Content> {
        FloatingMenuRoot(content: content) { [weak self] region in
            self?.window?.hitRegion = region
        }
    }
}

final class FloatingMenuWindow: UIWindow {
    var hitRegion: CGRect = .null

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !hitRegion.isNull, hitRegion.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    override var canBecomeKey: Bool { false }
}

struct FloatingMenuRoot<Content: View>: View {
    let content: Content
    let onHitRegion: @MainActor @Sendable (CGRect) -> Void

    var body: some View {
        content
            .environment(\.floatingMenuHitRegion, FloatingMenuHitRegionReporter(report: onHitRegion))
    }
}

struct FloatingMenuHitRegionReporter: Sendable {
    let report: @MainActor @Sendable (CGRect) -> Void
}

extension EnvironmentValues {
    @Entry var floatingMenuHitRegion = FloatingMenuHitRegionReporter { _ in }
}

private struct FloatingMenuHitRegionModifier: ViewModifier {
    @Environment(\.floatingMenuHitRegion) private var reporter

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { reporter.report($0) }
            .onDisappear { reporter.report(.null) }
    }
}

extension View {
    func floatingMenuHitRegion() -> some View {
        modifier(FloatingMenuHitRegionModifier())
    }
}
