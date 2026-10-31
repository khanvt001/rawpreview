//
//  CopyButton.swift
//  rawpreview
//

import SwiftUI

/// "Copy 12 to Shoot ⌘⏎" plus a menu to export them with the chosen preset,
/// change the destination, sort into date folders, or share the marked files. Shown in the grid's status bar
/// and over the Single Image view.
struct CopyButton: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PresetStore.self) private var presets

    var body: some View {
        @Bindable var library = library
        let count = library.checkedIDs.count
        let folder = library.copyDestination?.lastPathComponent
        let marked = library.items.filter { library.checkedIDs.contains($0.id) }

        Menu {
            Button("Copy \(count) Marked Files") { library.startCopy() }
            if let preset = presets.selectedPreset {
                // One JPEG per shot: a RAW+JPEG pair is exported once; videos are left out.
                let shots = Set(marked.filter(\.kind.isImage).map(\.sidecarURL)).count
                Button("Export \(shots == 1 ? "1 JPEG" : "\(shots) JPEGs") with “\(preset.title)”") {
                    library.startCopy(applying: preset)
                }
                .disabled(shots == 0)
                .help("Full-size JPEGs with the preset applied, one per shot, into the same destination")
            }
            Button("Change Destination…") { library.chooseCopyDestination() }
            Toggle("Sort into Date Folders", isOn: $library.copiesIntoDateFolders)
            Divider()
            ShareMenuItems(items: marked)
            Divider()
            Button("Clear Marks") { library.clearChecked() }
        } label: {
            Label(
                folder.map { "Copy \(count) to \($0)  ⌘⏎" } ?? "Copy \(count) marked…  ⌘⏎",
                systemImage: "checkmark.circle.fill"
            )
        } primaryAction: {
            library.startCopy()
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
        .focusable(false)
        .disabled(library.isCopying)
        .help(library.copyDestination.map { "Copy marked files to \($0.path(percentEncoded: false)) (⌘Return)" } ?? "Choose a folder and copy marked files (⌘Return)")
    }
}
