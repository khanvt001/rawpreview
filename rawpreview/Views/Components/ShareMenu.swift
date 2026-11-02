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
            .help("Makes \(ShareService.maxPixelSize) px JPEG copies (GPS removed) and opens the share sheet")
            Button("AirDrop as \(shots) JPEGs", systemImage: "dot.radiowaves.left.and.right") {
                SharingController.airDropJPEGs(of: images)
            }

            // Grouped, so the menu stays short and the look's name is said once.
            if let look = edits.exportLook(preset: presets.appliedPreset, for: images) {
                Menu {
                    Button("Share as \(shots) JPEGs…", systemImage: "photo") {
                        SharingController.shareJPEGs(of: images, look: look)
                    }
                    .help("Makes \(ShareService.maxPixelSize) px JPEG copies with the preset and each photo's edits applied (GPS removed) and opens the share sheet")
                    Button("AirDrop as \(shots) JPEGs", systemImage: "dot.radiowaves.left.and.right") {
                        SharingController.airDropJPEGs(of: images, look: look)
                    }
                } label: {
                    Label("With \(look.title)", systemImage: "camera.filters")
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
        prepareJPEGs(items, look: look) { urls in share(urls, from: anchor) }
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
        prepareJPEGs(items, look: look) { urls in
            guard let airDrop = NSSharingService(named: .sendViaAirDrop), airDrop.canPerform(withItems: urls) else {
                showError(String(localized: "AirDrop isn't available. Check that Wi-Fi and Bluetooth are on."))
                return
            }
            airDrop.perform(withItems: urls)
        }
    }

    @Observable final class Preparation {
        var completed = 0
        var total = 1
        var task: Task<Void, Never>?
    }

    private struct PreparationView: View {
        let operation: Preparation
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preparing JPEGs…").font(.headline)
                ProgressView(value: Double(operation.completed), total: Double(max(1, operation.total)))
                HStack {
                    Text("\(operation.completed) / \(operation.total)").monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel) { operation.task?.cancel() }
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }

    private static func prepareJPEGs(_ items: [PhotoItem], look: ExportLook?, completion: @escaping ([URL]) -> Void) {
        let configuration = ProcessingConfiguration.current
        let longEdge = ShareService.maxPixelSize
        let operation = Preparation()
        operation.total = Set(items.map(\.sidecarURL)).count
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = String(localized: "Preparing Photos")
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PreparationView(operation: operation))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        operation.task = Task {
            defer { panel.close(); operation.task = nil }
            do {
                let urls = try await ShareService.makeJPEGs(for: items, look: look, processing: configuration, longEdge: longEdge) { completed, total in
                    Task { @MainActor in
                        operation.completed = completed
                        operation.total = total
                    }
                }
                try Task.checkCancellation()
                panel.orderOut(nil)
                completion(urls)
            } catch is CancellationError {
                return
            } catch {
                panel.orderOut(nil)
                showError(error.localizedDescription)
            }
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
