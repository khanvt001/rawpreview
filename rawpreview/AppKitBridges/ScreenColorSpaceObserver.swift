//
//  ScreenColorSpaceObserver.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// Keeps `DisplayColorSpace` in sync with the window's screen: on launch,
/// when the window moves to another display, and when a display's colour
/// profile changes. Images decoded for the old screen are dropped from the
/// caches so new decodes match.
struct ScreenColorSpaceObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> ObserverView {
        ObserverView()
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private var observers: [any NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }

            for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeScreenProfileNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sync() }
                })
            }
            sync()
        }

        private func sync() {
            guard let space = (window?.screen ?? NSScreen.main)?.colorSpace?.cgColorSpace,
                  DisplayColorSpace.update(to: space)
            else { return }
            ThumbnailService.shared.removeAll()
            PreviewService.shared.removeAll()
        }
    }
}
