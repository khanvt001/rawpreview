//
//  LoupeView.swift
//  rawpreview
//

import AVKit
import SwiftUI

/// Single Image mode: zoomable image, filmstrip below, Info / Edit / Presets sidebar on the right.
struct LoupeView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PresetStore.self) private var presets
    @Environment(EditStore.self) private var edits

    @State private var image: CGImage?
    @State private var displayedPhotoID: PhotoItem.ID?
    @State private var loadID = UUID()
    @State private var displayedProcessing: ProcessingConfiguration?
    @State private var processingError: DevelopError?
    @State private var isRendering = false
    @AppStorage(ProcessingSource.defaultsKey) private var sourceSetting = ProcessingSource.embedded.rawValue
    @AppStorage(ProcessingSource.fallbackKey) private var fallbackData = Data()
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
        // The toolbar's Info / Edit / Presets toggles pick the page.
        .inspector(isPresented: $library.showsInspector) {
            VStack(spacing: 0) {
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
        // Delete stays in the Photo menu, context menu and ⌘⌫, away from
        // the sidebar buttons it used to sit next to.
        .toolbar {
            ToolbarItemGroup {
                sidebarToggle(.info, "Info", systemImage: "info.circle", help: "Show / hide info (I)")
                sidebarToggle(.edit, "Edit", systemImage: "slider.horizontal.3", help: "Show / hide edit (E)")
                    // Tinted while this photo has adjustments.
                    .foregroundStyle(edits.hasAdjustments(library.focusedID) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                sidebarToggle(.presets, "Presets", systemImage: "camera.filters", help: "Show / hide presets (P)")
                    // Tinted while a preset is applied (there is no filled variant).
                    .foregroundStyle(presets.activePreset == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
            }
        }
        .onDisappear { PreviewService.shared.prefetch([]) }
        .task(id: LoadKey(photo: library.focusedID, preset: presets.activePreset?.revision,
                          light: edits.adjustments(for: library.focusedID), processing: processing,
                          isHovering: presets.hoveredID != nil, full: !zoom.isAtFit)) {
            await load()
        }
    }

    /// A toolbar button that reads as pressed while the sidebar shows `tab`.
    private func sidebarToggle(
        _ tab: LibraryViewModel.InspectorTab,
        _ title: LocalizedStringKey,
        systemImage: String,
        help: LocalizedStringKey
    ) -> some View {
        Toggle(isOn: Binding(
            get: { library.showsInspector && library.inspectorTab == tab },
            set: { _ in library.toggleInspector(tab) }
        )) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .focusable(false)
        .help(help)
    }

    private var processing: ProcessingConfiguration {
        ProcessingConfiguration(source: ProcessingSource(rawValue: sourceSetting) ?? .embedded,
                                embeddedFallbacks: ProcessingConfiguration.decodeFallbacks(fallbackData))
    }

    private struct LoadKey: Equatable {
        let photo: PhotoItem.ID?
        let preset: UUID?
        let light: LightAdjustments
        let processing: ProcessingConfiguration
        let isHovering: Bool
        let full: Bool
    }

    @ViewBuilder
    private var imageArea: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let processingError {
                VStack(spacing: 12) {
                    ContentUnavailableView("Can't Process Photo", systemImage: "exclamationmark.triangle",
                                           description: Text(processingError.localizedDescription))
                    if case .unsupportedRAW(let url) = processingError {
                        Button("Use Embedded Preview for This Photo") {
                            ProcessingConfiguration.acceptEmbeddedFallback(for: url)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if let image {
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
            } else if let item = library.focusedItem, item.kind == .video {
                LoupeVideoPlayer(url: item.url)
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            if library.showsLoupeOverlays, let item = library.focusedItem {
                LoupeInfoBar(
                    item: item,
                    position: (library.focusedIndex ?? 0) + 1,
                    total: library.visibleItems.count,
                    isChecked: library.isChecked(item.id),
                    rating: library.rating(for: item.id),
                    zoom: image == nil ? nil : zoom,
                    preset: presets.activePreset,
                    isLoadingFullResolution: image != nil && isRendering && presets.hoveredID == nil
                )
                .padding(12)
            }
        }
        .contextMenu {
            if let item = library.focusedItem {
                PhotoContextMenu(item: item)
            }
        }
        // Top corner, so it never collides with the info bar on a narrow window.
        .overlay(alignment: .topTrailing) {
            if library.showsLoupeOverlays, !library.checkedIDs.isEmpty {
                CopyButton()
                    .padding(12)
            }
        }
        .animation(.easeOut(duration: 0.15), value: library.showsLoupeOverlays)
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
        let requestID = UUID()
        loadID = requestID
        processingError = nil
        isRendering = false
        guard let item = library.focusedItem, item.kind.isImage else {
            image = nil
            displayedPhotoID = nil
            exif = nil
            return
        }
        let configuration = processing
        let state = DevelopState(processing: configuration, preset: presets.activePreset,
                                 light: edits.adjustments(for: item.id))
        let hovering = presets.hoveredID != nil
        let full = !zoom.isAtFit
        if displayedPhotoID != item.id || displayedProcessing != configuration {
            image = nil
            isFullResolution = false
        }
        displayedPhotoID = item.id
        displayedProcessing = configuration
        isUnreadable = false
        isRendering = !hovering
        defer { if loadID == requestID { isRendering = false } }
        do {
            let source = await PhotoSourceResolver.resolve(item.url, processing: configuration)
            guard isCurrent(requestID, photo: item.id) else { return }
            if !hovering, let cached = DevelopService.cachedPreview(url: source, state: state, longEdge: full ? nil : 2048) {
                image = cached
                isFullResolution = full
                exif = MetadataService.shared.cachedExif(for: source) ?? exif
                return
            }
            if !hovering {
                let metadata = await MetadataService.shared.exif(for: source)
                guard isCurrent(requestID, photo: item.id) else { return }
                exif = metadata
            }
            // Zoomed in on this photo already: keep the sharp image until the
            // full-size render replaces it (~80 ms for 20 MP) rather than
            // flashing a 1024 px one at 100%.
            if !(full && isFullResolution && image != nil) || hovering {
                let quick = try await DevelopService.preview(url: source, state: state, longEdge: 1024,
                                                            purpose: hovering ? .hover : .selected, cacheOnly: hovering)
                guard isCurrent(requestID, photo: item.id) else { return }
                if let quick {
                    image = quick
                    isFullResolution = false
                }
            }
            guard !hovering else { return }
            try await Task.sleep(for: .milliseconds(150))
            guard isCurrent(requestID, photo: item.id) else { return }
            let settled = try await DevelopService.preview(url: source, state: state, longEdge: full ? nil : 2048)
            guard isCurrent(requestID, photo: item.id) else { return }
            if let settled {
                image = settled
                isFullResolution = full
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(requestID, photo: item.id) else { return }
            processingError = (error as? DevelopError) ?? .renderFailed
        }
    }

    private func isCurrent(_ request: UUID, photo: PhotoItem.ID) -> Bool {
        !Task.isCancelled && loadID == request && library.focusedID == photo
    }

}

/// Plays the focused video with the standard controls; paused when another
/// photo is focused or the view goes away.
private struct LoupeVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            // Room for the info bar under the controls.
            .padding(.bottom, 52)
            .task(id: url) {
                player?.pause()
                player = AVPlayer(url: url)
            }
            .onDisappear { player?.pause() }
    }
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
                Label(preset.titleWithAmount, systemImage: preset.compatibility.hasInvalidData ? "exclamationmark.triangle" : "camera.filters")
                    .foregroundStyle(.secondary)
                    .help(presetHelp(preset))
            }
            if isLoadingFullResolution {
                ProgressView()
                    .controlSize(.mini)
                    .help("Rendering photo…")
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
        let approximate = preset.compatibility.labels(for: .approximate)
        if !approximate.isEmpty { help += "\n" + String(localized: "Approximate: \(approximate.joined(separator: ", "))") }
        return help
    }
}
