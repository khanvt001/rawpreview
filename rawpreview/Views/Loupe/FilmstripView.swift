//
//  FilmstripView.swift
//  rawpreview
//

import SwiftUI

/// Horizontal strip of small thumbnails under the loupe; keeps the focused
/// photo centred as you navigate.
///
/// Shows only the photos around the current one (`radius` each side), not the
/// whole card: SwiftUI re-lays-out the strip on every photo change, and with
/// hundreds of items that work showed up as dropped frames while holding an
/// arrow key. The rest of the card is a keypress or the grid away.
struct FilmstripView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(\.displayScale) private var displayScale

    /// Drives the strip's scroll position. Using `scrollPosition` instead of
    /// `ScrollViewReader.scrollTo` in `onAppear` matters: when the loupe opens
    /// inside the split view, `onAppear` runs before the strip has its final
    /// layout and the jump is lost, leaving the strip at the first photo.
    @State private var scrolledID: PhotoItem.ID?

    private let side: CGFloat = 76
    private static let radius = 40

    /// When focus last changed, to tell a held arrow key from a single step.
    /// A plain reference box so updating it doesn't re-render the strip.
    @State private var focusClock = FocusClock()

    private final class FocusClock {
        var lastChange = Date.distantPast
    }

    var body: some View {
        let pixelSize = Int(side * displayScale)

        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(library.filmstripItems(radius: Self.radius)) { item in
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
            // Single steps glide; a held arrow key (repeats ~30×/s) snaps, as
            // restarting an animation on every repeat looks jittery.
            let isRepeating = Date.now.timeIntervalSince(focusClock.lastChange) < 0.2
            focusClock.lastChange = .now
            if isRepeating {
                scrolledID = id
            } else {
                withAnimation(.easeOut(duration: 0.15)) {
                    scrolledID = id
                }
            }
        }
        .frame(height: side + 16)
        .background(.bar)
    }
}
