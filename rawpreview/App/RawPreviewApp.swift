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
    @State private var edits = EditStore()

    init() {
        // Seed before the first thumbnails decode; the window's observer
        // refines it once the window is on screen.
        if let space = NSScreen.main?.colorSpace?.cgColorSpace {
            DisplayColorSpace.update(to: space)
        }
        Analytics.start()
        Analytics.track("app_started")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(presets)
                .environment(edits)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            ZoomCommands(library: library)
            PhotoCommands(library: library, edits: edits)
            CommandGroup(replacing: .appInfo) {
                Button("About RawPreview") { AppInfo.showAboutPanel() }
                SupportMenuButton()
            }
            CommandGroup(replacing: .importExport) {
                Button("Import Presets…") { presets.chooseAndImport() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }

        Window("Keyboard Shortcuts", id: KeyboardShortcutsView.windowID) {
            KeyboardShortcutsView()
        }
        .windowResizability(.contentSize)

        Window("Support RawPreview", id: SupportView.windowID) {
            SupportView()
        }
        .windowResizability(.contentSize)
    }
}
