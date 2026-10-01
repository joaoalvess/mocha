import SwiftUI
import UIKit

enum ImageViewerLayout {
    static let maximumZoom: CGFloat = 5
    static let doubleTapZoom: CGFloat = 2.5
    static let dismissDistance: CGFloat = 320
    static let dismissThreshold: CGFloat = 110
    static let dismissVelocity: CGFloat = 900
}

struct ZoomableImageView: UIViewRepresentable {
    let image: CGImage
    let onDragProgress: (CGFloat) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> ZoomableImageCoordinator {
        ZoomableImageCoordinator()
    }

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        context.coordinator.onDragProgress = onDragProgress
        context.coordinator.onDismiss = onDismiss
        view.display(image)
    }
}

final class ZoomingImageScrollView: UIScrollView {
    let imageView = UIImageView()
    private var imageAspect: CGFloat = 0
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        minimumZoomScale = 1
        maximumZoomScale = ImageViewerLayout.maximumZoom
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Imagem"
        imageView.accessibilityTraits = .image
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func display(_ image: CGImage) {
        if imageView.image?.cgImage !== image {
            imageView.image = UIImage(cgImage: image)
        }
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        guard abs(aspect - imageAspect) > 0.01 else { return }
        imageAspect = aspect
        resetLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize {
            resetLayout()
        }
        centerContent()
    }

    func centerContent() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset {
            contentInset = inset
        }
    }

    private func resetLayout() {
        guard imageAspect > 0, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        zoomScale = minimumZoomScale
        let fitsWidth = bounds.width / bounds.height < imageAspect
        let size = fitsWidth
            ? CGSize(width: bounds.width, height: bounds.width / imageAspect)
            : CGSize(width: bounds.height * imageAspect, height: bounds.height)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerContent()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }
}

@MainActor
final class ZoomableImageCoordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onDragProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    private weak var scrollView: ZoomingImageScrollView?
    private weak var dismissPan: UIPanGestureRecognizer?

    func attach(to view: ZoomingImageScrollView) {
        scrollView = view
        view.delegate = self
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)
        dismissPan = pan
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        (scrollView as? ZoomingImageScrollView)?.imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        (scrollView as? ZoomingImageScrollView)?.centerContent()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan, let view = scrollView, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard view.zoomScale <= view.minimumZoomScale + 0.01 else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === dismissPan
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view = scrollView else { return }
        if view.zoomScale > view.minimumZoomScale + 0.01 {
            view.setZoomScale(view.minimumZoomScale, animated: true)
            return
        }
        let point = recognizer.location(in: view.imageView)
        let size = CGSize(
            width: view.bounds.width / ImageViewerLayout.doubleTapZoom,
            height: view.bounds.height / ImageViewerLayout.doubleTapZoom
        )
        view.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    @objc private func handleDismissPan(_ pan: UIPanGestureRecognizer) {
        guard let view = scrollView else { return }
        let offset = max(0, pan.translation(in: view.superview).y)
        switch pan.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: offset)
            onDragProgress(min(1, offset / ImageViewerLayout.dismissDistance))
        case .ended:
            let velocity = pan.velocity(in: view.superview).y
            if offset > ImageViewerLayout.dismissThreshold || velocity > ImageViewerLayout.dismissVelocity {
                onDismiss()
            } else {
                restore(view)
            }
        case .cancelled, .failed:
            restore(view)
        default:
            break
        }
    }

    private func restore(_ view: UIView) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            view.transform = .identity
        }
        onDragProgress(0)
    }
}
