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
        // Flexible, not `.fixed(side)`: fixed columns report their total width
        // as the grid's minimum, which the window adopts as its minimum size —
        // and since `side` is derived from the current width, the window could
        // only ever grow. Flexible columns follow the width they're offered.
        let columns = Array(repeating: GridItem(.flexible(minimum: 1), spacing: spacing), count: columnCount)

        ScrollViewReader { proxy in
            ScrollView {
                grid(columns: columns, side: side, pixelSize: pixelSize)
            }
            // The grid adapts to any width, so never let it dictate one.
            .frame(minWidth: 200, maxWidth: .infinity)
            .overlay {
                if library.visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label("All Files Hidden", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Every file type is filtered out.")
                    } actions: {
                        Button("Show All") { library.showAllExtensions() }
                    }
                }
            }
            // Keep the keyboard-focused tile on screen (minimal scroll, no jump
            // when it is already visible).
            .onChange(of: library.focusedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
            .onAppear {
                if let id = library.focusedID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .onChange(of: columnCount, initial: true) { _, count in
            library.columnCount = count
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar()
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
                .focusable(false)
                .help("Thumbnail size")
            }
        }
    }

    private func grid(columns: [GridItem], side: CGFloat, pixelSize: Int) -> some View {
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
                .onTapGesture(count: 2) {
                    library.focusedID = item.id
                    library.viewMode = .loupe
                }
                // Simultaneous so a single click focuses immediately instead
                // of waiting out the double-click interval.
                .simultaneousGesture(TapGesture().onEnded {
                    library.focusedID = item.id
                })
            }
        }
        .padding(padding)
    }
}

/// "Copy 12 to Shoot ⏎" plus a menu to change the destination.
private struct CopyButton: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        let count = library.checkedIDs.count
        let folder = library.copyDestination?.lastPathComponent

        Menu {
            Button("Copy \(count) Marked Files") { library.startCopy() }
            Button("Change Destination…") { library.chooseCopyDestination() }
            Divider()
            Button("Clear Marks") { library.clearChecked() }
        } label: {
            Label(
                folder.map { "Copy \(count) to \($0)  ⏎" } ?? "Copy \(count) marked…  ⏎",
                systemImage: "checkmark.circle.fill"
            )
        } primaryAction: {
            library.startCopy()
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
        .focusable(false)
        .disabled(library.isCopying)
        .help(library.copyDestination.map { "Copy marked files to \($0.path(percentEncoded: false)) (Return)" } ?? "Choose a folder and copy marked files (Return)")
    }
}

private struct GridStatusBar: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            Text("\(library.visibleItems.count) of \(library.items.count) files")
            if !library.checkedIDs.isEmpty {
                CopyButton()
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
