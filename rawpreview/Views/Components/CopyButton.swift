//
//  CopyButton.swift
//  rawpreview
//

import SwiftUI

/// "Copy 12 to Shoot ⌘⏎" plus a menu to export them (format, size, preset and edits),
/// change the destination, sort into date folders, or share the marked files. Shown in the grid's status bar
/// and over the Single Image view.
struct CopyButton: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PresetStore.self) private var presets
    @Environment(EditStore.self) private var edits

    var body: some View {
        @Bindable var library = library
        let count = library.checkedIDs.count
        let folder = library.copyDestination?.lastPathComponent
        let marked = library.items.filter { library.checkedIDs.contains($0.id) }

        Menu {
            Button("Copy \(count) Marked Files") { library.startCopy() }
            // One file per shot: a RAW+JPEG pair is exported once; videos are left out.
            let shots = Set(marked.filter(\.kind.isImage).map(\.sidecarURL)).count
            Button("Export \(shots) Photos…") {
                library.showExportOptions(for: marked, look: edits.exportLook(preset: presets.appliedPreset, for: marked))
            }
            .disabled(shots == 0)
            .help("JPEG, HEIF or PNG files in the size you choose, with the preset and each photo's edits applied")
            Button("Change Destination…") { library.chooseCopyDestination() }
            Toggle("Sort into Date Folders", isOn: $library.copiesIntoDateFolders)
            Divider()
            ShareMenuItems(items: marked, offersExport: false)
            Divider()
            Button("Clear Marks") { library.clearChecked() }
        } label: {
            Label(
                folder.map { String(localized: "Copy \(count) to \($0)  ⌘⏎") } ?? String(localized: "Copy \(count) marked…  ⌘⏎"),
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
        .help(library.copyDestination.map { String(localized: "Copy marked files to \($0.path(percentEncoded: false)) (⌘Return)") } ?? String(localized: "Choose a folder and copy marked files (⌘Return)"))
    }
}
