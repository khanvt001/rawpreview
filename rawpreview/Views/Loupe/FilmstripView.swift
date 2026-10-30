//
//  FilmstripView.swift
//  rawpreview
//

import SwiftUI

/// Horizontal strip of small thumbnails under the loupe; keeps the focused
/// photo centred as you navigate.
struct FilmstripView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(\.displayScale) private var displayScale

    /// Drives the strip's scroll position. Using `scrollPosition` instead of
    /// `ScrollViewReader.scrollTo` in `onAppear` matters: when the loupe opens
    /// inside the split view, `onAppear` runs before the strip has its final
    /// layout and the jump is lost, leaving the strip at the first photo.
    @State private var scrolledID: PhotoItem.ID?

    private let side: CGFloat = 76

    var body: some View {
        let pixelSize = Int(side * displayScale)

        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
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
                    .contextMenu { PhotoContextMenu(item: item) }
                    .onTapGesture {
                        library.focusedID = item.id
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollPosition(id: $scrolledID, anchor: .center)
        .onAppear {
            scrolledID = library.focusedID
        }
        .onChange(of: library.focusedID) { _, id in
            withAnimation(.easeOut(duration: 0.15)) {
                scrolledID = id
            }
        }
        .frame(height: side + 16)
        .background(.bar)
    }
}
