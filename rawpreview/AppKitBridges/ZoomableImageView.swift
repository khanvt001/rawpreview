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

/// A zoom command from outside the view (keyboard / menu). `serial` makes
/// repeated identical commands (⌘+ ⌘+ ⌘+) distinct.
struct ZoomRequest: Equatable {
    enum Command {
        /// Fit ⇄ 100% (Z).
        case toggle
        /// Next step up / down the zoom ladder (⌘+ / ⌘−).
        case zoomIn, zoomOut
        /// Whole image in view (⌘0).
        case fit
    }

    let command: Command
    let serial: Int
}

/// Pixel-peeping image view: an `NSScrollView` with native magnification
/// (trackpad pinch, ⌥-scroll), double-click to toggle Fit ⇄ 100% at the
/// cursor, stepped zoom commands, and drag-to-pan.
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
    /// Latest keyboard / menu zoom command; each new `serial` runs once.
    let zoomRequest: ZoomRequest?
    let onZoomChange: (ZoomState) -> Void

    func makeNSView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateNSView(_ scrollView: ZoomingScrollView, context: Context) {
        scrollView.onZoomChange = onZoomChange
        scrollView.display(image, pixelSize: pixelSize)

        if let zoomRequest, zoomRequest.serial != context.coordinator.lastSerial {
            context.coordinator.lastSerial = zoomRequest.serial
            scrollView.perform(zoomRequest.command)
        }
    }

    func makeCoordinator() -> Coordinator {
        // Start from the current serial so a request made before this view
        // existed (e.g. in another photo's loupe) isn't replayed.
        Coordinator(lastSerial: zoomRequest?.serial ?? 0)
    }

    final class Coordinator {
        var lastSerial: Int

        init(lastSerial: Int) {
            self.lastSerial = lastSerial
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
    /// Where zoom is heading. While an animated zoom runs, `magnification` is
    /// still the old value, so quick repeated ⌘+ presses must step from here.
    private var targetMagnification: CGFloat = 1

    private static let maximumZoom: CGFloat = 8
    private static let animationDuration: TimeInterval = 0.18
    /// ⌘+ / ⌘− stops (Fit sits below wherever it falls for the window).
    static let zoomSteps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 1, 1.5, 2, 3, 4, 6, 8]

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        documentView = imageView
        drawsBackground = false
        contentView.drawsBackground = false
        // No scroll bars, like Preview / Lightroom: pan by dragging or
        // scrolling. With a mouse attached macOS forces legacy scroll bars,
        // which appear on the first zoom-in and shrink the viewport, shifting
        // the image under the cursor mid-zoom.
        hasHorizontalScroller = false
        hasVerticalScroller = false
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
        if targetMagnification < 0.999 {
            zoom(to: 1, at: point, animated: true)
        } else if isAtFit {
            zoom(to: 2, at: point, animated: true) // Small image already fits at 100%.
        } else {
            fit(animated: true)
        }
    }

    func perform(_ command: ZoomRequest.Command) {
        switch command {
        case .toggle: toggleZoom(at: nil)
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .fit: fit(animated: true)
        }
    }

    /// Next step above the current zoom, around the centre of the view.
    func zoomIn() {
        let target = Self.zoomSteps.first { $0 > targetMagnification + 0.001 } ?? Self.maximumZoom
        zoom(to: target, at: nil, animated: true)
    }

    /// Next step below the current zoom; the last step out is Fit.
    func zoomOut() {
        let fit = fitMagnification
        if let target = Self.zoomSteps.last(where: { $0 < targetMagnification - 0.001 && $0 > fit + 0.001 }) {
            zoom(to: target, at: nil, animated: true)
        } else {
            self.fit(animated: true)
        }
    }

    /// ⌥ + scroll wheel (or two-finger scroll) zooms smoothly around the
    /// cursor; plain scrolling still pans.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.option), event.scrollingDeltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        // Same physical direction zooms the same way whatever the user's
        // "natural scrolling" setting: away from you / up = zoom in.
        var delta = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { delta = -delta }
        // Trackpads send many small pixel deltas; mouse wheels send ~1 per notch.
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.15
        let target = min(max(targetMagnification * exp(delta * sensitivity), fitMagnification), Self.maximumZoom)
        zoom(to: target, at: imageView.convert(event.locationInWindow, from: nil), animated: false)
    }

    /// Zooms to `target`, keeping `point` (document coordinates; `nil` = centre
    /// of the visible area) fixed on screen.
    private func zoom(to target: CGFloat, at point: NSPoint?, animated: Bool) {
        let fit = fitMagnification
        let anchor = point ?? NSPoint(x: documentVisibleRect.midX, y: documentVisibleRect.midY)
        isAtFit = abs(target - fit) < 0.002
        targetMagnification = target
        minMagnification = min(fit, target)
        // Despite the name, `centeredAt` keeps `anchor` fixed on screen rather
        // than centring it: exactly "zoom in where I clicked".
        animateMagnification(to: target, centeredAt: anchor, animated: animated)
        report(magnification: target)
    }

    /// One zoom animation at a time, driven by a display link. AppKit's
    /// `animator().setMagnification` animations overlap badly when commands
    /// arrive quickly (⌘+ ⌘+ ⌘0 settled just below Fit in testing); here a new
    /// command simply restarts the animation from the current zoom.
    private struct ZoomAnimation {
        let from: CGFloat
        let to: CGFloat
        let anchor: NSPoint
        let start: CFTimeInterval
    }

    private var zoomAnimation: ZoomAnimation?
    private var zoomDisplayLink: CADisplayLink?

    private func animateMagnification(to target: CGFloat, centeredAt anchor: NSPoint, animated: Bool) {
        guard animated, window != nil, magnification > 0 else {
            stopZoomAnimation()
            setMagnification(target, centeredAt: anchor)
            return
        }
        zoomAnimation = ZoomAnimation(from: magnification, to: target, anchor: anchor, start: CACurrentMediaTime())
        if zoomDisplayLink == nil {
            let link = displayLink(target: self, selector: #selector(stepZoomAnimation))
            link.add(to: .main, forMode: .common)
            zoomDisplayLink = link
        }
    }

    @objc private func stepZoomAnimation(_ link: CADisplayLink) {
        guard let animation = zoomAnimation else {
            stopZoomAnimation()
            return
        }
        let progress = min(1, (CACurrentMediaTime() - animation.start) / Self.animationDuration)
        let eased = 1 - pow(1 - progress, 3) // ease-out cubic
        // Interpolate geometrically so 25%→50% feels as fast as 200%→400%.
        let value = animation.from * pow(animation.to / animation.from, eased)
        setMagnification(progress >= 1 ? animation.to : value, centeredAt: animation.anchor)
        if progress >= 1 {
            stopZoomAnimation()
        }
    }

    private func stopZoomAnimation() {
        zoomAnimation = nil
        zoomDisplayLink?.invalidate()
        zoomDisplayLink = nil
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
        targetMagnification = fit
        let center = NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        animateMagnification(to: fit, centeredAt: center, animated: animated)
        report(magnification: fit)
    }

    override func magnify(with event: NSEvent) {
        stopZoomAnimation() // A pinch takes over from any running zoom animation.
        super.magnify(with: event)
    }

    @objc private func liveMagnifyDidEnd(_ notification: Notification) {
        targetMagnification = magnification
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
