//
//  DisplayColorSpace.swift
//  rawpreview
//

import CoreGraphics
import Synchronization

/// The colour space of the screen the window is on, which decoded images are
/// converted into (`ImageDecoder.prepareForDisplay`).
///
/// Core Animation colour-matches every image to the display before drawing
/// it. If the image isn't already in the display's colour space and pixel
/// layout, that happens on the main thread at commit time: measured ~80 ms
/// for a 20 MP photo on an external monitor, enough to stall the filmstrip
/// on every arrow press. Pre-converted, the same swap takes under 1 ms.
nonisolated enum DisplayColorSpace {
    private static let current = Mutex<CGColorSpace>(CGColorSpace(name: CGColorSpace.sRGB)!)

    static var target: CGColorSpace {
        current.withLock { $0 }
    }

    /// Returns `true` when the target actually changed.
    @discardableResult
    static func update(to space: CGColorSpace) -> Bool {
        current.withLock { existing in
            guard existing != space else { return false }
            existing = space
            return true
        }
    }
}
