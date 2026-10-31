//
//  CopyButton.swift
//  rawpreview
//

import SwiftUI

/// "Copy 12 to Shoot ⌘⏎" plus a menu to change the destination, sort into
/// date folders, or share the marked files. Shown in the grid's status bar
/// and over the Single Image view.
struct CopyButton: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library
        let count = library.checkedIDs.count
        let folder = library.copyDestination?.lastPathComponent

        Menu {
            Button("Copy \(count) Marked Files") { library.startCopy() }
            Button("Change Destination…") { library.chooseCopyDestination() }
            Toggle("Sort into Date Folders", isOn: $library.copiesIntoDateFolders)
            Divider()
            ShareMenuItems(items: library.items.filter { library.checkedIDs.contains($0.id) })
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
