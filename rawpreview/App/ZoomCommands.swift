//
//  ZoomCommands.swift
//  rawpreview
//

import SwiftUI

/// View menu items for Single Image zoom, so the shortcuts are discoverable
/// and work wherever keyboard focus is.
struct ZoomCommands: Commands {
    let library: LibraryViewModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Section {
                Button("Zoom In") { library.requestZoom(.zoomIn) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { library.requestZoom(.zoomOut) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Zoom to Fit") { library.requestZoom(.fit) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Toggle Fit / 100%") { library.requestZoom(.toggle) }
            }
            .disabled(library.viewMode != .loupe)
        }
    }
}
