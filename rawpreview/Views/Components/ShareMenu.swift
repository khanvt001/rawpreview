//
//  ShareMenu.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// Share actions for one or more photos, used in the grid / filmstrip context
/// menus and the toolbar's Share menu.
struct ShareMenuItems: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PresetStore.self) private var presets
    @Environment(EditStore.self) private var edits
    let items: [PhotoItem]
    /// Export & Share… (the Export dialog for `items`); off where the menu
    /// already has its own Export item.
    var offersExport = true

    var body: some View {
        let count = items.count
        let images = items.filter(\.kind.isImage)

        // Originals go through SwiftUI's ShareLink, which lists every share
        // service (AirDrop, Mail, Messages…) as a submenu.
        ShareLink(items: items.map(\.url)) {
            Label(count == 1 ? "Share Original" : "Share \(count) Originals", systemImage: "square.and.arrow.up")
        }

        if !images.isEmpty {
            // One JPEG per shot: a RAW+JPEG pair is shared once.
            let shots = Set(images.map(\.sidecarURL)).count
            Button("Share as \(shots) JPEGs…", systemImage: "photo") {
                SharingController.shareJPEGs(of: images)
            }
            .help("Makes 2048 px JPEG copies (GPS removed) and opens the share sheet")
            Button("AirDrop as \(shots) JPEGs", systemImage: "dot.radiowaves.left.and.right") {
                SharingController.airDropJPEGs(of: images)
            }

            if let look = edits.exportLook(preset: presets.appliedPreset, for: images) {
                Divider()
                Button("Share as \(shots) JPEGs with \(look.title)…", systemImage: "camera.filters") {
                    SharingController.shareJPEGs(of: images, look: look)
                }
                .help("Makes 2048 px JPEG copies with the preset and each photo's edits applied (GPS removed) and opens the share sheet")
                Button("AirDrop as \(shots) JPEGs with \(look.title)", systemImage: "dot.radiowaves.left.and.right") {
                    SharingController.airDropJPEGs(of: images, look: look)
                }
            }

            if offersExport {
                Divider()
                Button("Export & Share…", systemImage: "square.and.arrow.up.on.square") {
                    library.showExportOptions(for: images, look: edits.exportLook(preset: presets.appliedPreset, for: images))
                }
                .disabled(library.isCopying)
                .help("Choose format, quality and size, then save the files to a folder or share them")
            }
        }
    }
}

/// Generates temporary JPEGs and hands them, or files already written, to
/// AppKit sharing.
@MainActor
enum SharingController {
    /// Where a share picker opens: the pointer's position when the click
    /// happened, kept until the files are ready.
    struct Anchor {
        let window: NSWindow
        let location: NSPoint

        /// The pointer in `window` (default: the key window) right now.
        static func pointer(in window: NSWindow? = NSApp.keyWindow) -> Anchor? {
            window.map { Anchor(window: $0, location: $0.mouseLocationOutsideOfEventStream) }
        }
    }

    static func shareJPEGs(of items: [PhotoItem], look: ExportLook? = nil) {
        let anchor = Anchor.pointer()
        Analytics.track("photos_shared", ["count": items.count, "via": "share_sheet", "with_preset": look?.preset != nil, "with_edits": look?.adjustments.isEmpty == false])
        Task {
            guard let urls = await makeJPEGs(items, look: look) else { return }
            share(urls, from: anchor)
        }
    }

    /// The share picker (AirDrop, Messages, Mail…) for files already written.
    static func share(_ urls: [URL], from anchor: Anchor?) {
        guard !urls.isEmpty, let anchor, let view = anchor.window.contentView else { return }
        let point = view.convert(anchor.location, from: nil)
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: NSRect(origin: point, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
    }

    static func airDropJPEGs(of items: [PhotoItem], look: ExportLook? = nil) {
        Analytics.track("photos_shared", ["count": items.count, "via": "airdrop", "with_preset": look?.preset != nil, "with_edits": look?.adjustments.isEmpty == false])
        Task {
            guard let urls = await makeJPEGs(items, look: look) else { return }
            guard let airDrop = NSSharingService(named: .sendViaAirDrop), airDrop.canPerform(withItems: urls) else {
                showError(String(localized: "AirDrop isn't available. Check that Wi-Fi and Bluetooth are on."))
                return
            }
            airDrop.perform(withItems: urls)
        }
    }

    private static func makeJPEGs(_ items: [PhotoItem], look: ExportLook?) async -> [URL]? {
        do {
            return try await ShareService.makeJPEGs(for: items, look: look)
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't Share")
        alert.informativeText = message
        alert.runModal()
    }
}

/// Right-click menu for a photo in the grid or filmstrip.
struct PhotoContextMenu: View {
    @Environment(LibraryViewModel.self) private var library
    let item: PhotoItem

    var body: some View {
        let targets = library.actionTargets(for: item)

        ShareMenuItems(items: targets)
        Divider()
        Button(library.isChecked(item.id) ? "Unmark for Copy" : "Mark for Copy") {
            library.toggleChecked(item.id)
        }
        Menu("Rating") {
            ForEach(0...Rating.maxStars, id: \.self) { stars in
                Button(stars == 0 ? String(localized: "None") : String(repeating: "★", count: stars)) {
                    library.setRating(Rating(stars), for: item.id)
                }
            }
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url))
        }
        Divider()
        Button(targets.count == 1 ? "Delete…" : "Delete \(targets.count) Files…", role: .destructive) {
            library.requestDelete(targets)
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }
}
