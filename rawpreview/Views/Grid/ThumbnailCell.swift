//
//  ThumbnailCell.swift
//  rawpreview
//

import SwiftUI

/// One grid tile: thumbnail, check badge, rating and a mini EXIF line.
///
/// Takes plain values rather than reading the view model, so a cell's body only
/// re-runs when its own state changes.
struct ThumbnailCell: View {
    let item: PhotoItem
    let side: CGFloat
    let pixelSize: Int
    let isChecked: Bool
    let isFocused: Bool
    let rating: Rating
    let onToggleCheck: () -> Void

    @State private var image: CGImage?
    @State private var exif: ExifInfo?
    @State private var isHovering = false

    init(
        item: PhotoItem,
        side: CGFloat,
        pixelSize: Int,
        isChecked: Bool,
        isFocused: Bool,
        rating: Rating,
        onToggleCheck: @escaping () -> Void
    ) {
        self.item = item
        self.side = side
        self.pixelSize = pixelSize
        self.isChecked = isChecked
        self.isFocused = isFocused
        self.rating = rating
        self.onToggleCheck = onToggleCheck
        // Seed from cache so scrolling back paints on the first frame, no flash.
        _image = State(initialValue: ThumbnailService.shared.cachedThumbnail(for: item.url, pixelSize: pixelSize))
        _exif = State(initialValue: MetadataService.shared.cachedExif(for: item.url))
    }

    /// Small tiles drop the text overlays to keep the grid readable.
    private var showsDetails: Bool { side >= 120 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isChecked ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.fill.quaternary))
            thumbnail
                .padding(showsDetails ? 8 : 4)
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topLeading) {
            if showsDetails {
                extensionBadge
            }
        }
        .overlay(alignment: .topTrailing) {
            checkButton
        }
        .overlay(alignment: .bottom) {
            if showsDetails {
                infoBar
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: isFocused ? 3 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .task(id: LoadKey(url: item.url, bucket: ThumbnailService.bucket(for: pixelSize))) {
            await load()
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            Image(systemName: item.kind == .video ? "film" : "photo")
                .font(.system(size: side / 5))
                .foregroundStyle(.tertiary)
        }
    }

    private var extensionBadge: some View {
        Text(item.fileExtension)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
    }

    @ViewBuilder
    private var checkButton: some View {
        if isChecked || isHovering {
            Button(action: onToggleCheck) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: showsDetails ? 18 : 14, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isChecked ? Color.accentColor : Color.black.opacity(0.35))
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
            }
            .buttonStyle(.plain)
            .padding(5)
            .help(isChecked ? "Unmark for copy (S)" : "Mark for copy (S)")
        }
    }

    @ViewBuilder
    private var infoBar: some View {
        let summary = exif?.summaryLine ?? ""
        if rating.isRated || !summary.isEmpty {
            VStack(spacing: 2) {
                if rating.isRated {
                    RatingStarsView(rating: rating)
                }
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
        }
    }

    // MARK: - Loading

    private struct LoadKey: Hashable {
        let url: URL
        let bucket: Int
    }

    /// Cancelled automatically when the cell scrolls out of the lazy grid.
    private func load() async {
        guard item.kind.isImage else { return }
        let url = item.url
        async let thumbnail = ThumbnailService.shared.thumbnail(for: url, pixelSize: pixelSize)
        async let metadata = MetadataService.shared.exif(for: url)

        if let thumbnail = await thumbnail {
            image = thumbnail
        }
        if exif == nil, let metadata = await metadata {
            exif = metadata
        }
    }
}
