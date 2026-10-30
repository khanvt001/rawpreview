//
//  LoupeView.swift
//  rawpreview
//

import SwiftUI

/// Single Image mode: the focused image, fit to the window.
/// Phase 5 adds pixel-level zoom, the filmstrip and the EXIF sidebar.
struct LoupeView: View {
    @Environment(LibraryViewModel.self) private var library

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
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
                    rating: library.rating(for: item.id)
                )
                .padding(12)
            }
        }
        .task(id: library.focusedID) {
            await load()
        }
    }

    private func load() async {
        guard let item = library.focusedItem, item.kind.isImage else {
            image = nil
            return
        }

        // Paint whatever is already in memory (full image or grid thumbnail) on
        // this frame, then upgrade to full resolution.
        image = PreviewService.shared.cachedImage(for: item.url)

        let neighbours = library.neighbours(of: item.id, radius: 2).filter(\.kind.isImage)
        PreviewService.shared.prefetch(neighbours.map(\.url))

        if PreviewService.shared.cachedFullResolution(for: item.url) == nil,
           let full = await PreviewService.shared.fullResolution(for: item.url),
           !Task.isCancelled {
            image = full
        }
    }
}

private struct LoupeInfoBar: View {
    let item: PhotoItem
    let position: Int
    let total: Int
    let isChecked: Bool
    let rating: Rating

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
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}
