//
//  LoupeView.swift
//  rawpreview
//

import SwiftUI

/// Single Image mode: zoomable image, filmstrip below, EXIF inspector on the right.
struct LoupeView: View {
    @Environment(LibraryViewModel.self) private var library

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
            if let item = library.focusedItem {
                MetadataInspector(
                    item: item,
                    isChecked: library.isChecked(item.id),
                    rating: library.rating(for: item.id),
                    ratingStorage: library.ratingStorage(for: item.id)
                )
                .inspectorColumnWidth(min: 240, ideal: 300, max: 440)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Delete", systemImage: "trash") {
                    library.requestDeleteForFocused()
                }
                .focusable(false)
                .disabled(library.focusedItem == nil)
                .help("Delete this photo permanently, or all marked photos if it is marked (⌘⌫)")
            }
            ToolbarItem {
                Button("Info", systemImage: "info.circle") {
                    library.showsInspector.toggle()
                }
                .focusable(false)
                .help("Show / hide info (I)")
            }
        }
        .task(id: library.focusedID) {
            await load()
        }
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
                    description: Text("\(library.focusedItem?.fileName ?? "This file") may be damaged or in an unsupported format.")
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

        // 1. Paint whatever is in memory (full image or a thumbnail) this frame.
        let full = PreviewService.shared.cachedFullResolution(for: item.url)
        exif = MetadataService.shared.cachedExif(for: item.url)
        image = full ?? PreviewService.shared.placeholder(for: item.url)
        isFullResolution = full != nil
        isUnreadable = false

        // Screen-sharp previews for the next few photos are cheap (~25 ms each
        // from the embedded JPEG), so warm them right away.
        let neighbours = library.neighbours(of: item.id, radius: 3).filter(\.kind.isImage)
        ThumbnailService.shared.prefetch(neighbours.map(\.url), pixelSize: Self.navigationPixelSize)

        if exif == nil {
            exif = await MetadataService.shared.exif(for: item.url)
        }
        guard full == nil else { return }

        // 2. A 1024 px image looks sharp at Fit and is ready almost at once.
        if (image?.width ?? 0) < Self.navigationPixelSize,
           let preview = await ThumbnailService.shared.thumbnail(for: item.url, pixelSize: Self.navigationPixelSize),
           !Task.isCancelled {
            image = preview
        }

        // 3. Full resolution (for zooming) only once navigation pauses. While an
        //    arrow key is held, each step cancels this task here, so photos you
        //    skip past never pay for a 20 MP decode and swap.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        PreviewService.shared.prefetch(library.neighbours(of: item.id, radius: 1).filter(\.kind.isImage).map(\.url))

        let loaded = await PreviewService.shared.fullResolution(for: item.url)
        guard !Task.isCancelled else { return }
        if let loaded {
            image = loaded
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
}
