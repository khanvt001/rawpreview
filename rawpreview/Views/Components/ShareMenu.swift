//
//  ShareMenu.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// Share actions for one or more photos, used in the grid / filmstrip context
/// menus and the toolbar's Share menu.
struct ShareMenuItems: View {
    @Environment(PresetStore.self) private var presets
    let items: [PhotoItem]

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
            let noun = shots == 1 ? "JPEG" : "\(shots) JPEGs"
            Button("Share as \(noun)…", systemImage: "photo") {
                SharingController.shareJPEGs(of: images)
            }
            .help("Makes 2048 px JPEG copies (GPS removed) and opens the share sheet")
            Button("AirDrop as \(noun)", systemImage: "dot.radiowaves.left.and.right") {
                SharingController.airDropJPEGs(of: images)
            }

            if let preset = presets.selectedPreset {
                Divider()
                Button("Share as \(noun) with “\(preset.title)”…", systemImage: "camera.filters") {
                    SharingController.shareJPEGs(of: images, preset: preset)
                }
                .help("Makes 2048 px JPEG copies with the preset applied (GPS removed) and opens the share sheet")
                Button("AirDrop as \(noun) with “\(preset.title)”", systemImage: "dot.radiowaves.left.and.right") {
                    SharingController.airDropJPEGs(of: images, preset: preset)
                }
            }
        }
    }
}

/// Generates temporary JPEGs and hands them to AppKit sharing.
@MainActor
enum SharingController {
    static func shareJPEGs(of items: [PhotoItem], preset: DevelopPreset? = nil) {
        // Remember where the click happened; the picker is anchored there once
        // the JPEGs are ready.
        let window = NSApp.keyWindow
        let mouse = window?.mouseLocationOutsideOfEventStream
        Task {
            guard let urls = await makeJPEGs(items, preset: preset),
                  let window, let mouse, let view = window.contentView
            else { return }
            let point = view.convert(mouse, from: nil)
            let picker = NSSharingServicePicker(items: urls)
            picker.show(relativeTo: NSRect(origin: point, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
        }
    }

    static func airDropJPEGs(of items: [PhotoItem], preset: DevelopPreset? = nil) {
        Task {
            guard let urls = await makeJPEGs(items, preset: preset) else { return }
            guard let airDrop = NSSharingService(named: .sendViaAirDrop), airDrop.canPerform(withItems: urls) else {
                showError("AirDrop isn't available. Check that Wi-Fi and Bluetooth are on.")
                return
            }
            airDrop.perform(withItems: urls)
        }
    }

    private static func makeJPEGs(_ items: [PhotoItem], preset: DevelopPreset?) async -> [URL]? {
        do {
            return try await ShareService.makeJPEGs(for: items, preset: preset)
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Share"
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
                Button(stars == 0 ? "None" : String(repeating: "★", count: stars)) {
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
