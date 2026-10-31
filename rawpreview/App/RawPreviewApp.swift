//
//  RawPreviewApp.swift
//  rawpreview
//
//  Created by khanvt001 on 30/10/26.
//

import SwiftUI

@main
struct RawPreviewApp: App {
    @State private var library = LibraryViewModel()
    @State private var presets = PresetStore()

    init() {
        // Seed before the first thumbnails decode; the window's observer
        // refines it once the window is on screen.
        if let space = NSScreen.main?.colorSpace?.cgColorSpace {
            DisplayColorSpace.update(to: space)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(presets)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            ZoomCommands(library: library)
        }
    }
}
