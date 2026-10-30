//
//  LibraryContentView.swift
//  rawpreview
//

import SwiftUI

/// Hosts Grid / Single Image mode and owns the power-user keyboard:
///
/// | Key        | Action                                  |
/// |------------|-----------------------------------------|
/// | ← → ↑ ↓    | Move focus (↑↓ jump a row in the grid)  |
/// | Space      | Toggle Grid ⇄ Single Image              |
/// | Esc        | Back to Grid                            |
/// | S          | Mark / unmark for copy                  |
/// | 1–5, 0     | Set / clear star rating                 |
/// | Z          | Single Image: toggle Fit ⇄ 100%         |
/// | I          | Single Image: show / hide info sidebar  |
struct LibraryContentView: View {
    @Environment(LibraryViewModel.self) private var library
    @FocusState private var hasKeyFocus: Bool

    var body: some View {
        @Bindable var library = library

        Group {
            switch library.viewMode {
            case .grid: PhotoGridView()
            case .loupe: LoupeView()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyFocus)
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        // Take key focus back from the sidebar / toolbar whenever the user
        // interacts with the photos.
        .simultaneousGesture(TapGesture().onEnded { hasKeyFocus = true })
        .onChange(of: library.focusedID) { hasKeyFocus = true }
        .onChange(of: library.viewMode) { hasKeyFocus = true }
        .onAppear { hasKeyFocus = true }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("View Mode", selection: $library.viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(LibraryViewModel.ViewMode.grid)
                    Label("Single Image", systemImage: "photo").tag(LibraryViewModel.ViewMode.loupe)
                }
                .pickerStyle(.segmented)
                .focusable(false)
                .disabled(library.focusedID == nil)
                .help("Toggle Grid / Single Image (Space)")
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Leave ⌘/⌃/⌥ combinations to menus and the system.
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }

        switch press.key {
        case .leftArrow: library.moveFocus(.left)
        case .rightArrow: library.moveFocus(.right)
        case .upArrow: library.moveFocus(.up)
        case .downArrow: library.moveFocus(.down)
        default:
            // Everything else is a toggle or a set: holding the key must not repeat it.
            guard press.phase == .down else { return .handled }
            return handleCommandKey(press)
        }
        return .handled
    }

    private func handleCommandKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space:
            library.toggleViewMode()
            return .handled
        case .escape where library.viewMode == .loupe:
            library.viewMode = .grid
            return .handled
        default:
            break
        }

        let character = press.characters.lowercased()
        switch character {
        case "s":
            library.toggleCheckedForFocused()
            return .handled
        case "z" where library.viewMode == .loupe:
            library.requestZoomToggle()
            return .handled
        case "i" where library.viewMode == .loupe:
            library.showsInspector.toggle()
            return .handled
        default:
            break
        }
        if let stars = Int(character), (0...Rating.maxStars).contains(stars) {
            library.setRatingForFocused(Rating(stars))
            return .handled
        }
        return .ignored
    }
}
