//
//  PhotoCommands.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// The Photo menu, View menu items for the sidebar, and Help ▸ Keyboard
/// Shortcuts, so every culling action can be found without knowing its key.
///
/// Single-letter keys (S, 1–5, I…) stay out of the menus: AppKit matches
/// menu key equivalents before a text field sees the key, so they would
/// fire while typing in a search box. The Keyboard Shortcuts window lists them.
struct PhotoCommands: Commands {
    let library: LibraryViewModel
    let edits: EditStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Photo") {
            let item = library.focusedItem
            Button(item.map { library.isChecked($0.id) } == true ? "Unmark for Copy" : "Mark for Copy") {
                library.toggleCheckedForFocused()
            }
            .disabled(item == nil)

            Menu("Rating") {
                ForEach(0...Rating.maxStars, id: \.self) { stars in
                    Button(stars == 0 ? String(localized: "None") : String(repeating: "★", count: stars)) {
                        library.setRatingForFocused(Rating(stars))
                    }
                }
            }
            .disabled(item == nil)

            Divider()

            Button("Copy Edits") {
                if let item { edits.copyAdjustments(of: item.id) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(item?.kind.isImage != true || library.isSearchFocused)
            Button(pasteTitle(item)) {
                if let item { edits.pasteAdjustments(onto: library.actionTargets(for: item)) }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(item == nil || edits.copiedAdjustments == nil || library.isSearchFocused)

            Divider()

            Button("Copy Marked Files") { library.startCopy() }
                .keyboardShortcut(.return, modifiers: .command)
                // ⌘ keys in a text field belong to the field.
                .disabled(library.checkedIDs.isEmpty || library.isCopying || library.isSearchFocused)
            Button("Clear Marks") { library.clearChecked() }
                .disabled(library.checkedIDs.isEmpty)

            Divider()

            Button("Show in Finder") {
                if let item {
                    NSWorkspace.shared.activateFileViewerSelecting(library.actionTargets(for: item).map(\.url))
                }
            }
            .disabled(item == nil)
            Button("Delete…") { library.requestDeleteForFocused() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(item == nil || library.isSearchFocused)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find File Names") { library.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(before: .toolbar) {
            Section {
                Button(library.viewMode == .grid ? "Show Single Image" : "Show Grid") {
                    library.toggleViewMode()
                }
                .disabled(library.focusedID == nil)
            }
            Section {
                Button("Info") { library.toggleInspector(.info) }
                Button("Edit") { library.toggleInspector(.edit) }
                Button("Presets") { library.toggleInspector(.presets) }
            }
            .disabled(library.viewMode != .loupe)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: KeyboardShortcutsView.windowID) }
                .keyboardShortcut("/", modifiers: .command)
        }
    }

    /// "Paste Edits", or "Paste Edits to 12 Photos" when the focused photo
    /// is marked and the paste goes to every marked one.
    private func pasteTitle(_ item: PhotoItem?) -> String {
        let count = item.map { library.actionTargets(for: $0).count } ?? 0
        return count > 1 ? String(localized: "Paste Edits to \(count) Photos") : String(localized: "Paste Edits")
    }
}

/// Every key the photo views understand, grouped like the menus.
struct KeyboardShortcutsView: View {
    static let windowID = "shortcuts"

    private struct ShortcutGroup {
        let title: LocalizedStringKey
        /// Keys are localizable too, for words like "Double-click".
        let rows: [(keys: LocalizedStringKey, action: LocalizedStringKey)]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Browse", rows: [
            ("← → ↑ ↓", "Move between photos"),
            ("Space", "Grid ⇄ Single Image"),
            ("Esc", "Back to the grid"),
            ("⌘F", "Search file names"),
        ]),
        ShortcutGroup(title: "Cull", rows: [
            ("S  ↩", "Mark / unmark for copy"),
            ("⇧-click", "Mark every photo up to this one"),
            ("1 – 5", "Set star rating"),
            ("0", "Clear rating"),
            ("⌘↩", "Copy marked files"),
            ("⌘⌫", "Delete (all marked, if this photo is marked)"),
        ]),
        ShortcutGroup(title: "Single Image", rows: [
            ("Z", "Fit ⇄ 100%"),
            ("⌘+  ⌘−  ⌘0", "Zoom in / out / to fit"),
            ("⌘- or ⌥-scroll", "Zoom around the pointer"),
            ("I  E  P", "Info / Edit / Presets sidebar"),
            ("[  ]", "Previous / next preset"),
            ("\\", "Preset before / after"),
            ("H", "Hide / show the overlays"),
        ]),
        ShortcutGroup(title: "Edit", rows: [
            ("⌘⇧C  ⌘⇧V", "Copy / paste edits"),
            ("Double-click", "Reset a slider"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                Section(group.title) {
                    ForEach(group.rows.indices, id: \.self) { row in
                        let row = group.rows[row]
                        LabeledContent {
                            Text(row.keys)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(row.action)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
