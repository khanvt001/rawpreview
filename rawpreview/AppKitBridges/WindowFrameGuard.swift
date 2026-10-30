//
//  WindowFrameGuard.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// Pulls the hosting window back inside its screen's visible area when it
/// opens larger than the screen or hanging off it, which happens when macOS
/// restores a bad saved frame (e.g. one from a disconnected display, or the
/// oversized frame an earlier build's grid produced).
struct WindowFrameGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView {
        GuardView()
    }

    func updateNSView(_ nsView: GuardView, context: Context) {}

    final class GuardView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Wait one turn so state restoration has applied the saved frame.
            DispatchQueue.main.async { [weak self] in
                self?.fitWindowToScreen()
            }
        }

        private func fitWindowToScreen() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            var frame = window.frame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            if frame != window.frame {
                window.setFrame(frame, display: true)
            }
        }
    }
}
