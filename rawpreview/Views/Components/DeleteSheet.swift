//
//  DeleteSheet.swift
//  rawpreview
//

import SwiftUI

/// Confirms a delete (erased on cards, to the Trash elsewhere), showing the
/// photos that will go, with an option to take the other half of each
/// RAW+JPEG pair along.
struct DeleteSheet: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library
        let targets = library.pendingDeletion ?? []
        let paired = library.pairedFiles(of: targets)
        let total = targets.count + (library.deletesPairedFiles ? paired.count : 0)
        let permanently = library.deletesPermanently

        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title(targets, permanently: permanently))
                    .font(.headline)
            } icon: {
                Image(systemName: "trash.fill").foregroundStyle(permanently ? .red : .secondary)
            }

            DeletePreviewStrip(items: targets)

            Text(permanently
                 ? "This can’t be undone: files on a memory card are erased, not moved to the Trash, so their space is freed at once."
                 : "The files are moved to the Trash, where they can be put back from Finder.")
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
                Button(buttonTitle(total, permanently: permanently), role: .destructive) {
                    library.confirmDeletion()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func title(_ targets: [PhotoItem], permanently: Bool) -> String {
        switch (targets.count == 1, permanently) {
        case (true, true): String(localized: "Permanently delete “\(targets[0].fileName)”?")
        case (false, true): String(localized: "Permanently delete \(targets.count) files?")
        case (true, false): String(localized: "Move “\(targets[0].fileName)” to the Trash?")
        case (false, false): String(localized: "Move \(targets.count) files to the Trash?")
        }
    }

    private func buttonTitle(_ total: Int, permanently: Bool) -> String {
        switch (total == 1, permanently) {
        case (true, true): String(localized: "Delete")
        case (false, true): String(localized: "Delete \(total) Files")
        case (true, false): String(localized: "Move to Trash")
        case (false, false): String(localized: "Move \(total) Files to Trash")
        }
    }

    /// "JPEG", "RAW" or "JPEG/RAW", from the files that would go along.
    private static func kinds(of items: [PhotoItem]) -> String {
        let names = Set(items.map { $0.kind == .raw ? "RAW" : $0.fileExtension })
        return names.sorted().joined(separator: "/")
    }
}

/// The first few photos about to be deleted, so ⌘⌫ on a marked photo (which
/// takes every marked one along) never surprises.
private struct DeletePreviewStrip: View {
    let items: [PhotoItem]
    private static let limit = 6
    private let side: CGFloat = 52

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(Self.limit)) { item in
                DeletePreviewTile(item: item, side: side)
            }
            if items.count > Self.limit {
                Text(verbatim: "+\(items.count - Self.limit)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: side, height: side)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

private struct DeletePreviewTile: View {
    let item: PhotoItem
    let side: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.fill.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(item.fileName)
        .task {
            guard item.kind.isImage else { return }
            image = ThumbnailService.shared.cachedQuickThumbnail(for: item.url)
            if image == nil {
                image = await ThumbnailService.shared.thumbnail(for: item.url, pixelSize: Int(side * displayScale))
            }
        }
    }
}
