//
//  PhotoGridView.swift
//  rawpreview
//

import SwiftUI

/// Grid mode: a lazily-loaded grid of thumbnails with a size slider.
struct PhotoGridView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(\.displayScale) private var displayScale
    @AppStorage("gridThumbnailSize") private var thumbnailSize = 180.0

    @State private var availableWidth: CGFloat = 0

    static let sizeRange: ClosedRange<Double> = 100...420
    private let spacing: CGFloat = 8
    private let padding: CGFloat = 12

    /// Fixed column count (rather than `.adaptive`) so the view model knows how
    /// far Up/Down should jump.
    private var columnCount: Int {
        let usable = availableWidth - padding * 2 + spacing
        return max(1, Int(usable / (thumbnailSize + spacing)))
    }

    private var side: CGFloat {
        let count = CGFloat(columnCount)
        let usable = availableWidth - padding * 2 - spacing * (count - 1)
        return max(1, (usable / count).rounded(.down))
    }

    var body: some View {
        let side = side
        let pixelSize = Int(side * displayScale)
        let columns = Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columnCount)

        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(library.visibleItems) { item in
                    ThumbnailCell(
                        item: item,
                        side: side,
                        pixelSize: pixelSize,
                        isChecked: library.isChecked(item.id),
                        isFocused: library.focusedID == item.id,
                        rating: library.rating(for: item.id),
                        onToggleCheck: { library.toggleChecked(item.id) }
                    )
                    .id(item.id)
                    .onTapGesture {
                        library.focusedID = item.id
                    }
                }
            }
            .padding(padding)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .onChange(of: columnCount, initial: true) { _, count in
            library.columnCount = count
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GridStatusBar()
        }
        .toolbar {
            ToolbarItem {
                Slider(value: $thumbnailSize, in: Self.sizeRange) {
                    Text("Thumbnail Size")
                } minimumValueLabel: {
                    Image(systemName: "photo").imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: "photo").imageScale(.large)
                }
                .frame(width: 160)
                .help("Thumbnail size")
            }
        }
    }
}

private struct GridStatusBar: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            Text("\(library.visibleItems.count) of \(library.items.count) files")
            if !library.checkedIDs.isEmpty {
                Label("\(library.checkedIDs.count) marked for copy", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            if let item = library.focusedItem {
                Text(item.fileName)
                Text(item.fileSize.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
