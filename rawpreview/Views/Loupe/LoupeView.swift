//
//  LoupeView.swift
//  rawpreview
//

import SwiftUI

/// Single Image mode: zoomable image, filmstrip below, Info / Edit / Presets sidebar on the right.
struct LoupeView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PresetStore.self) private var presets
    @Environment(EditStore.self) private var edits

    @State private var image: CGImage?
    @State private var isFullResolution = false
    /// Neither a thumbnail nor the full image could be decoded.
    @State private var isUnreadable = false
    @State private var exif: ExifInfo?
    @State private var zoom = ZoomState(percent: 100, isAtFit: true)

    var body: some View {
        @Bindable var library = library

        VStack(spacing: 0) {
            imageArea
            Divider()
            FilmstripView()
        }
        .inspector(isPresented: $library.showsInspector) {
            VStack(spacing: 0) {
                Picker("Sidebar", selection: $library.inspectorTab) {
                    Text("Info").tag(LibraryViewModel.InspectorTab.info)
                    Text("Edit").tag(LibraryViewModel.InspectorTab.edit)
                    Text("Presets").tag(LibraryViewModel.InspectorTab.presets)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .focusable(false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()

                switch library.inspectorTab {
                case .info:
                    if let item = library.focusedItem {
                        MetadataInspector(
                            item: item,
                            isChecked: library.isChecked(item.id),
                            rating: library.rating(for: item.id),
                            ratingStorage: library.ratingStorage(for: item.id)
                        )
                    } else {
                        Spacer()
                    }
                case .edit:
                    EditInspector(item: library.focusedItem, image: image)
                case .presets:
                    PresetInspector()
                }
            }
            .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
        }
        .toolbar {
            ToolbarItem {
                Button("Delete", systemImage: "trash") {
                    library.requestDeleteForFocused()
                }
                .focusable(false)
                .disabled(library.focusedItem == nil)
                .help("Delete this photo, or all marked photos if it is marked (⌘⌫)")
            }
            ToolbarItem {
                Button("Edit", systemImage: "slider.horizontal.3") {
                    library.toggleInspector(.edit)
                }
                // Tinted while this photo has adjustments.
                .foregroundStyle(edits.hasAdjustments(library.focusedID) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .focusable(false)
                .help("Show / hide edit (E)")
            }
            ToolbarItem {
                Button("Presets", systemImage: "camera.filters") {
                    library.toggleInspector(.presets)
                }
                // Tinted while a preset is applied (there is no filled variant).
                .foregroundStyle(presets.activePreset == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
                .focusable(false)
                .help("Show / hide presets (P)")
            }
            ToolbarItem {
                Button("Info", systemImage: "info.circle") {
                    library.toggleInspector(.info)
                }
                .focusable(false)
                .help("Show / hide info (I)")
            }
        }
        .task(id: LoadKey(photo: library.focusedID, preset: renderPreset?.revision)) {
            await load()
        }
    }

    /// The applied preset with this photo's Edit adjustments on top.
    private var renderPreset: DevelopPreset? {
        edits.preset(applying: presets.activePreset, to: library.focusedID)
    }

    /// Reload when the photo, the applied preset or its adjustments change.
    private struct LoadKey: Equatable {
        let photo: PhotoItem.ID?
        let preset: UUID?
    }

    @ViewBuilder
    private var imageArea: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let image {
                ZoomableImageView(
                    image: image,
                    pixelSize: displayPixelSize(for: image),
                    zoomRequest: library.zoomRequest,
                    onZoomChange: { zoom = $0 }
                )
            } else if isUnreadable {
                ContentUnavailableView(
                    "Can't Preview",
                    systemImage: "exclamationmark.triangle",
                    description: Text(library.focusedItem.map { String(localized: "\($0.fileName) may be damaged or in an unsupported format.") }
                                      ?? String(localized: "This file may be damaged or in an unsupported format."))
                )
            } else if library.focusedItem?.kind == .video {
                ContentUnavailableView("Video", systemImage: "film", description: Text("Videos can't be previewed yet."))
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            if let item = library.focusedItem {
                LoupeInfoBar(
                    item: item,
                    position: (library.focusedIndex ?? 0) + 1,
                    total: library.visibleItems.count,
                    isChecked: library.isChecked(item.id),
                    rating: library.rating(for: item.id),
                    zoom: image == nil ? nil : zoom,
                    preset: presets.activePreset,
                    isLoadingFullResolution: image != nil && !isFullResolution
                )
                .padding(12)
            }
        }
        .contextMenu {
            if let item = library.focusedItem {
                PhotoContextMenu(item: item)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !library.checkedIDs.isEmpty {
                CopyButton()
                    .padding(12)
            }
        }
    }

    /// Full-resolution geometry even while a thumbnail placeholder is shown, so
    /// zoom doesn't jump when the full image arrives. Once it has, its real
    /// size wins (a RAW decode can crop a few pixels off the EXIF size).
    private func displayPixelSize(for image: CGImage) -> CGSize {
        if isFullResolution {
            return CGSize(width: image.width, height: image.height)
        }
        return exif?.orientedPixelSize ?? CGSize(width: image.width, height: image.height)
    }

    private func load() async {
        guard let item = library.focusedItem, item.kind.isImage else {
            image = nil
            exif = nil
            return
        }

        let preset = renderPreset

        // 1. Paint whatever is in memory (full image or a thumbnail) this frame.
        //    Thumbnails take the preset inline, so a photo never flashes
        //    unedited; a full image is shown only if its render is cached.
        let full = PreviewService.shared.cachedFullResolution(for: item.url)
        let fullReady = full.flatMap { PresetRenderer.cached($0, preset: preset, url: item.url) }
        exif = MetadataService.shared.cachedExif(for: item.url)
        image = fullReady ?? PreviewService.shared.placeholder(for: item.url).map {
            PresetRenderer.render($0, preset: preset, url: item.url)
        }
        isFullResolution = fullReady != nil
        isUnreadable = false

        // Screen-sharp previews for the next few photos are cheap (~25 ms each
        // from the embedded JPEG), so warm them right away.
        let neighbours = library.neighbours(of: item.id, radius: 3).filter(\.kind.isImage)
        ThumbnailService.shared.prefetch(neighbours.map(\.url), pixelSize: Self.navigationPixelSize)

        if exif == nil {
            exif = await MetadataService.shared.exif(for: item.url)
        }
        guard fullReady == nil else { return }

        // 2. A 1024 px image looks sharp at Fit and is ready almost at once.
        if (image?.width ?? 0) < Self.navigationPixelSize,
           let preview = await ThumbnailService.shared.thumbnail(for: item.url, pixelSize: Self.navigationPixelSize),
           !Task.isCancelled {
            image = PresetRenderer.render(preview, preset: preset, url: item.url)
        }

        // 3. Full resolution (for zooming) only once navigation pauses. While an
        //    arrow key is held, each step cancels this task here, so photos you
        //    skip past never pay for a 20 MP decode and swap. Already decoded
        //    (only the preset or a slider changed): a shorter pause, so a
        //    slider drag shows the quick preview and renders full size once
        //    it slows down.
        try? await Task.sleep(for: .milliseconds(full == nil ? 150 : 60))
        guard !Task.isCancelled else { return }
        PreviewService.shared.prefetch(library.neighbours(of: item.id, radius: 1).filter(\.kind.isImage).map(\.url))

        let loaded = await PreviewService.shared.fullResolution(for: item.url)
        guard !Task.isCancelled else { return }
        if let loaded {
            let rendered = await PresetRenderer.renderDetached(loaded, preset: preset, url: item.url)
            guard !Task.isCancelled else { return }
            image = rendered
            isFullResolution = true
        } else if image == nil {
            isUnreadable = true
        }
    }

    /// Longest side of the image shown while moving between photos.
    private static let navigationPixelSize = 1024
}

private struct LoupeInfoBar: View {
    let item: PhotoItem
    let position: Int
    let total: Int
    let isChecked: Bool
    let rating: Rating
    let zoom: ZoomState?
    let preset: DevelopPreset?
    let isLoadingFullResolution: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isChecked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Text(item.fileName)
                .fontWeight(.semibold)
            if rating.isRated {
                RatingStarsView(rating: rating, size: 11)
            }
            Text("\(position) / \(total)")
                .foregroundStyle(.secondary)
            if let zoom {
                Divider().frame(height: 12)
                Text(zoom.isAtFit ? "Fit (\(Int(zoom.percent))%)" : "\(Int(zoom.percent))%")
                    .foregroundStyle(.secondary)
                    .help("Z or double-click: Fit / 100% · ⌘+ ⌘− ⌘0 · ⌘-scroll, ⌥-scroll or pinch to zoom")
            }
            if let preset {
                Divider().frame(height: 12)
                Label(preset.titleWithAmount, systemImage: preset.unsupportedSettings.isEmpty ? "camera.filters" : "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(presetHelp(preset))
            }
            if isLoadingFullResolution {
                ProgressView()
                    .controlSize(.mini)
                    .help("Loading full resolution…")
            }
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    private func presetHelp(_ preset: DevelopPreset) -> String {
        var help = String(localized: "Previewing preset “\(preset.title)” (approximate) · \\ shows before / after")
        if let summary = preset.summary {
            help += "\n\(summary)"
        }
        if !preset.unsupportedSettings.isEmpty {
            help += "\n" + String(localized: "Not previewed: \(preset.unsupportedSettings.joined(separator: ", "))")
        }
        return help
    }
}
