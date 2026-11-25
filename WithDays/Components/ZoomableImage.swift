import SwiftUI
import UIKit

/// An image in a scroll view: pinch to zoom, double-tap to zoom in or out, a tap and a long press for the caller.
struct GalleryZoomableImage: UIViewRepresentable {
    let image: UIImage
    var zoomEnabled = true
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    /// Told when the photo starts or stops being zoomed in.
    var onZoom: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GalleryZoomScroll {
        let scroll = GalleryZoomScroll()
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.boundsChanged() }
        scroll.delegate = context.coordinator
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.decelerationRate = .fast
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        scroll.addSubview(view)
        context.coordinator.scroll = scroll
        context.coordinator.imageView = view

        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        single.require(toFail: double)
        scroll.addGestureRecognizer(single)
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        long.minimumPressDuration = 0.5
        scroll.addGestureRecognizer(long)
        context.coordinator.double = double
        return scroll
    }

    func updateUIView(_ scroll: GalleryZoomScroll, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onLongPress = onLongPress
        coordinator.onZoom = onZoom
        scroll.maximumZoomScale = zoomEnabled ? 5 : 1
        scroll.pinchGestureRecognizer?.isEnabled = zoomEnabled
        coordinator.double?.isEnabled = zoomEnabled
        if !zoomEnabled, scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: true) }
        if coordinator.imageView?.image !== image {
            coordinator.imageView?.image = image
            scroll.zoomScale = 1
            coordinator.layout()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: UIScrollView?
        weak var imageView: UIImageView?
        weak var double: UITapGestureRecognizer?
        var onTap: (() -> Void)?
        var onLongPress: (() -> Void)?
        var onZoom: ((Bool) -> Void)?
        private var zoomed = false
        private var lastSize: CGSize = .zero

        func boundsChanged() {
            guard let scroll, scroll.bounds.size != lastSize else { return }
            scroll.zoomScale = 1
            layout()
        }

        /// Fits the image in the scroll view at zoom 1.
        func layout() {
            guard let scroll, let imageView, let image = imageView.image else { return }
            let bounds = scroll.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }
            lastSize = bounds
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
            center()
        }

        func center() {
            guard let scroll, let imageView else { return }
            let bounds = scroll.bounds.size
            let frame = imageView.frame
            scroll.contentInset = UIEdgeInsets(
                top: max((bounds.height - frame.height) / 2, 0),
                left: max((bounds.width - frame.width) / 2, 0),
                bottom: 0, right: 0
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center()
            let now = scrollView.zoomScale > 1.01
            if now != zoomed {
                zoomed = now
                onZoom?(now)
            }
        }

        @objc func tap() { onTap?() }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { onLongPress?() }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// Tells its coordinator when it's laid out, so the image fits the real size.
final class GalleryZoomScroll: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
