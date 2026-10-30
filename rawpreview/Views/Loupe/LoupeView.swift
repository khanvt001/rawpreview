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

        // Paint whatever is already in memory (full image or grid thumbnail) on
        // this frame, then upgrade to full resolution.
        let full = PreviewService.shared.cachedFullResolution(for: item.url)
        exif = MetadataService.shared.cachedExif(for: item.url)
        image = full ?? PreviewService.shared.placeholder(for: item.url)
        isFullResolution = full != nil

        let neighbours = library.neighbours(of: item.id, radius: 2).filter(\.kind.isImage)
        PreviewService.shared.prefetch(neighbours.map(\.url))

        if exif == nil {
            exif = await MetadataService.shared.exif(for: item.url)
        }
        if full == nil, let loaded = await PreviewService.shared.fullResolution(for: item.url), !Task.isCancelled {
            image = loaded
            isFullResolution = true
        }
    }
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
                    .help("Z or double-click: Fit / 100% · ⌘+ ⌘− ⌘0 · ⌥-scroll or pinch to zoom")
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
