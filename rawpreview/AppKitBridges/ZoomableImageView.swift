//
//  ZoomableImageView.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// Current zoom, reported back to SwiftUI for the zoom readout.
struct ZoomState: Equatable {
    /// 100 = one image pixel per screen pixel.
    var percent: Double
    var isAtFit: Bool
}

/// Pixel-peeping image view: an `NSScrollView` with native magnification
/// (trackpad pinch), double-click to toggle Fit ⇄ 100% at the cursor, and
/// drag-to-pan.
///
/// The image is drawn as `CALayer` contents rather than through `NSImageView`'s
/// drawing, so zooming and panning are pure GPU compositing of an already
/// decoded bitmap, and above 100% we can switch to nearest-neighbour sampling
/// to show real sensor pixels instead of a smoothed blur.
struct ZoomableImageView: NSViewRepresentable {
    let image: CGImage?
    /// Full-resolution pixel size of the photo, even while `image` is still a
    /// smaller placeholder, so geometry and zoom don't jump when it upgrades.
    let pixelSize: CGSize
    /// Bumped by the view model (the Z key) to toggle Fit ⇄ 100%.
    let zoomToggleRequest: Int
    let onZoomChange: (ZoomState) -> Void

    func makeNSView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateNSView(_ scrollView: ZoomingScrollView, context: Context) {
        scrollView.onZoomChange = onZoomChange
        scrollView.display(image, pixelSize: pixelSize)

        if context.coordinator.lastZoomToggleRequest != zoomToggleRequest {
            context.coordinator.lastZoomToggleRequest = zoomToggleRequest
            scrollView.toggleZoom(at: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastZoomToggleRequest: zoomToggleRequest)
    }

    final class Coordinator {
        var lastZoomToggleRequest: Int

        init(lastZoomToggleRequest: Int) {
            self.lastZoomToggleRequest = lastZoomToggleRequest
        }
    }
}

// MARK: - Scroll view

final class ZoomingScrollView: NSScrollView {
    var onZoomChange: ((ZoomState) -> Void)?

    private let imageView = ImageLayerView()
    private var pixelSize: CGSize = .zero
    private(set) var isAtFit = true
    private var lastReported: ZoomState?

    private static let maximumZoom: CGFloat = 8
    private static let animationDuration: TimeInterval = 0.18

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        documentView = imageView
        drawsBackground = false
        contentView.drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        maxMagnification = Self.maximumZoom

        imageView.onDoubleClick = { [weak self] point in
            self?.toggleZoom(at: point)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(liveMagnifyDidEnd),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: self
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `image`. Navigating between photos of the same size keeps the
    /// current zoom and position, so focus can be compared across a burst; a
    /// different size starts again from Fit.
    func display(_ image: CGImage?, pixelSize newPixelSize: CGSize) {
        imageView.image = image
        guard newPixelSize != pixelSize, newPixelSize.width > 0, newPixelSize.height > 0 else { return }
        pixelSize = newPixelSize
        imageView.frame = NSRect(origin: .zero, size: documentSize)
        fit(animated: false)
    }

    /// Double-click / Z: below 100% → 100% with `point` held under the cursor;
    /// otherwise back to Fit. `point` is in document coordinates; `nil` zooms
    /// around the centre of what is visible.
    func toggleZoom(at point: NSPoint?) {
        let fit = fitMagnification
        let target: CGFloat
        if magnification < 0.999 {
            target = 1
        } else if isAtFit {
            target = 2 // Image already fits at 100% (small file): go to 200%.
        } else {
            self.fit(animated: true)
            return
        }

        let anchor = point ?? NSPoint(x: documentVisibleRect.midX, y: documentVisibleRect.midY)
        isAtFit = abs(target - fit) < 0.001
        minMagnification = min(fit, target)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            // Despite the name, `centeredAt` keeps `anchor` fixed on screen
            // rather than centring it: exactly "zoom in where I clicked".
            animator().setMagnification(target, centeredAt: anchor)
        }
        report(magnification: target)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let fit = fitMagnification
        if isAtFit {
            if abs(magnification - fit) > 0.0001 || minMagnification != fit {
                self.fit(animated: false)
            }
        } else {
            minMagnification = min(fit, magnification)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Points-per-pixel changed (moved to a non-Retina display): 100% must
        // still mean one image pixel per screen pixel.
        guard pixelSize != .zero else { return }
        imageView.frame = NSRect(origin: .zero, size: documentSize)
        fit(animated: false)
    }

    // MARK: Helpers

    /// Document size in points such that magnification 1.0 is exactly 100%.
    private var documentSize: CGSize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }

    /// Largest magnification that shows the whole image, never upscaling past 100%.
    private var fitMagnification: CGFloat {
        let document = imageView.frame.size
        let available = contentSize
        guard document.width > 0, document.height > 0, available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / document.width, available.height / document.height, 1)
    }

    private func fit(animated: Bool) {
        let fit = fitMagnification
        minMagnification = fit
        isAtFit = true
        let center = NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.animationDuration
                animator().setMagnification(fit, centeredAt: center)
            }
        } else {
            setMagnification(fit, centeredAt: center)
        }
        report(magnification: fit)
    }

    @objc private func liveMagnifyDidEnd(_ notification: Notification) {
        isAtFit = abs(magnification - fitMagnification) < 0.002
        report(magnification: magnification)
    }

    private func report(magnification: CGFloat) {
        imageView.isPannable = !isAtFit
        imageView.usesNearestNeighbour = magnification > 1.001
        let state = ZoomState(percent: (magnification * 100).rounded(), isAtFit: isAtFit)
        guard state != lastReported else { return }
        lastReported = state
        // Deferred: this can run inside SwiftUI's `updateNSView`, where
        // mutating view state is not allowed.
        Task { [onZoomChange] in onZoomChange?(state) }
    }
}

// MARK: - Clip view

/// Keeps a smaller-than-viewport image centred instead of pinned bottom-left.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width {
            rect.origin.x = (document.frame.width - rect.width) / 2
        }
        if rect.height > document.frame.height {
            rect.origin.y = (document.frame.height - rect.height) / 2
        }
        return rect
    }
}

// MARK: - Image layer

private final class ImageLayerView: NSView {
    var onDoubleClick: ((NSPoint) -> Void)?

    var image: CGImage? {
        didSet {
            guard image !== oldValue else { return }
            layer?.contents = image
        }
    }

    /// Zoomed in beyond Fit: drag pans and the cursor shows a hand.
    var isPannable = false {
        didSet {
            guard isPannable != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Above 100% show hard-edged pixels (what focus checking needs); below,
    /// filter smoothly so the downscaled image doesn't shimmer.
    var usesNearestNeighbour = false {
        didSet {
            layer?.magnificationFilter = usesNearestNeighbour ? .nearest : .linear
        }
    }

    private var lastDragLocation: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {} // Contents are set directly in `image`.

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
            return
        }
        guard isPannable else { return }
        lastDragLocation = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragLocation, let scrollView = enclosingScrollView else { return }
        let location = event.locationInWindow
        lastDragLocation = location

        // Window and (unflipped) document coordinates both grow upward, so the
        // visible rect moves opposite to the drag, scaled by the zoom.
        let clip = scrollView.contentView
        let scale = scrollView.magnification
        var origin = clip.bounds.origin
        origin.x -= (location.x - last.x) / scale
        origin.y -= (location.y - last.y) / scale
        clip.setBoundsOrigin(clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    override func mouseUp(with event: NSEvent) {
        guard lastDragLocation != nil else { return }
        lastDragLocation = nil
        NSCursor.pop()
    }

    override func resetCursorRects() {
        if isPannable {
            addCursorRect(visibleRect, cursor: .openHand)
        }
    }
}
