//
//  ThumbnailCell.swift
//  rawpreview
//

import SwiftUI

/// One grid tile: thumbnail, check badge, rating, file name and a mini EXIF line.
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
    /// Decoding finished without an image (corrupt or unsupported file).
    @State private var isUnreadable = false

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
        _image = State(initialValue: ThumbnailService.shared.cachedThumbnail(for: item.url, pixelSize: pixelSize)
            ?? ThumbnailService.shared.cachedQuickThumbnail(for: item.url))
        _exif = State(initialValue: MetadataService.shared.cachedExif(for: item.url))
    }

    /// Small tiles drop the text overlays to keep the grid readable; Settings
    /// can turn them off everywhere.
    private var showsDetails: Bool { side >= 120 && showsInfoOverlay }
    @AppStorage("gridShowsInfo") private var showsInfoOverlay = true

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
            // An outline with a light inner edge, so the focused tile reads
            // differently from a marked one (accent tint and check badge).
            if isFocused {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                RoundedRectangle(cornerRadius: 6)
                    .inset(by: 3)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        // One element for VoiceOver: name, state and the mark action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.fileName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isFocused ? [.isImage, .isSelected] : .isImage)
        .accessibilityAction(named: isChecked ? Text("Unmark for Copy") : Text("Mark for Copy"), onToggleCheck)
        .onHover { isHovering = $0 }
        .task(id: LoadKey(url: item.url, bucket: ThumbnailService.bucket(for: pixelSize))) {
            await load()
        }
    }

    /// "Marked, 3 of 5 stars, f/2.8 1/250 ISO 200".
    private var accessibilityValue: String {
        var parts: [String] = []
        if isChecked { parts.append(String(localized: "Marked")) }
        if rating.isRated { parts.append(String(localized: "\(rating.rawValue) of \(Rating.maxStars) stars")) }
        if isUnreadable { parts.append(String(localized: "Can't read this file")) }
        if let summary = exif?.summaryLine, !summary.isEmpty { parts.append(summary) }
        return parts.joined(separator: ", ")
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
        } else if isUnreadable {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: side / 5))
                .foregroundStyle(.secondary)
                .help("Can't read \(item.fileName). The file may be damaged or in an unsupported format.")
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
        VStack(spacing: 2) {
            if rating.isRated {
                RatingStarsView(rating: rating)
            }
            Text(item.fileName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                // Camera names differ at the end (DSC_6248), so keep that visible.
                .truncationMode(.middle)
                .foregroundStyle(.white)
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

    // MARK: - Loading

    private struct LoadKey: Hashable {
        let url: URL
        let bucket: Int
    }

    /// Cancelled automatically when the cell scrolls out of the lazy grid.
    private func load() async {
        guard item.kind.isImage else { return }
        let url = item.url
        // Queue the real thumbnail first so cells take their card-read turns
        // in layout order (top-left first) …
        async let thumbnail = ThumbnailService.shared.thumbnail(for: url, pixelSize: pixelSize)
        async let metadata = MetadataService.shared.exif(for: url)

        // … and show the embedded EXIF thumbnail while waiting for it.
        if image == nil, let quick = await ThumbnailService.shared.quickThumbnail(for: url) {
            image = quick
        }
        if let thumbnail = await thumbnail {
            image = thumbnail
        } else if !Task.isCancelled, image == nil {
            isUnreadable = true
        }
        if exif == nil, let metadata = await metadata {
            exif = metadata
        }
    }
}
