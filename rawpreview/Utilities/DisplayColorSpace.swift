//
//  DisplayColorSpace.swift
//  rawpreview
//

import CoreGraphics
import os

/// The colour space of the screen the window is on, which decoded images are
/// converted into (`ImageDecoder.prepareForDisplay`).
///
/// Core Animation colour-matches every image to the display before drawing
/// it. If the image isn't already in the display's colour space and pixel
/// layout, that happens on the main thread at commit time: measured ~80 ms
/// for a 20 MP photo on an external monitor, enough to stall the filmstrip
/// on every arrow press. Pre-converted, the same swap takes under 1 ms.
nonisolated enum DisplayColorSpace {
    private static let current = OSAllocatedUnfairLock(initialState: (space: CGColorSpace(name: CGColorSpace.sRGB)!, generation: 0))

    static var target: CGColorSpace {
        current.withLock { $0.space }
    }

    static var generation: Int { current.withLock { $0.generation } }

    /// Returns `true` when the target actually changed.
    @discardableResult
    static func update(to space: CGColorSpace) -> Bool {
        current.withLock { existing in
            guard existing.space != space else { return false }
            existing.space = space
            existing.generation += 1
            return true
        }
    }
}
