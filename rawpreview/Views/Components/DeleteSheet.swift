//
//  DeleteSheet.swift
//  rawpreview
//

import SwiftUI

/// Confirms a permanent delete, with an option to take the other half of
/// each RAW+JPEG pair along.
struct DeleteSheet: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library
        let targets = library.pendingDeletion ?? []
        let paired = library.pairedFiles(of: targets)
        let total = targets.count + (library.deletesPairedFiles ? paired.count : 0)

        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(targets.count == 1
                     ? "Permanently delete “\(targets[0].fileName)”?"
                     : "Permanently delete \(targets.count) files?")
                    .font(.headline)
            } icon: {
                Image(systemName: "trash.fill").foregroundStyle(.red)
            }

            Text("This can’t be undone: the files are erased, not moved to the Trash.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if !paired.isEmpty {
                Toggle(isOn: $library.deletesPairedFiles) {
                    Text("Also delete the matching \(Self.kinds(of: paired)) with the same name (\(paired.count) files)")
                }
                .help(paired.prefix(5).map(\.fileName).joined(separator: ", ") + (paired.count > 5 ? "…" : ""))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { library.pendingDeletion = nil }
                    .keyboardShortcut(.cancelAction)
                // No Return shortcut: Return marks photos, and a stray press
                // must not erase files.
                Button(total == 1 ? "Delete" : "Delete \(total) Files", role: .destructive) {
                    library.confirmDeletion()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// "JPEG", "RAW" or "JPEG/RAW", from the files that would go along.
    private static func kinds(of items: [PhotoItem]) -> String {
        let names = Set(items.map { $0.kind == .raw ? "RAW" : $0.fileExtension })
        return names.sorted().joined(separator: "/")
    }
}
