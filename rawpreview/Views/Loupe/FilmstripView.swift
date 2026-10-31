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
/// arrow key. Scrolling the strip by hand towards either end grows it by
/// another `radius` photos at a time; the next focus change shrinks it back.
struct FilmstripView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(\.displayScale) private var displayScale

    /// Drives the strip's scroll position. Using `scrollPosition` instead of
    /// `ScrollViewReader.scrollTo` in `onAppear` matters: when the loupe opens
    /// inside the split view, `onAppear` runs before the strip has its final
    /// layout and the jump is lost, leaving the strip at the first photo.
    @State private var scrolledID: PhotoItem.ID?

    /// Photos added beyond `radius` by scrolling, before / after the focused one.
    @State private var extraBefore = 0
    @State private var extraAfter = 0

    private let side: CGFloat = 76
    private static let radius = 40
    /// Grow once the scroll position is this close to an end of the strip:
    /// more than a strip's width, so the new photos are laid out before
    /// they're reached.
    private static let growMargin = 30

    /// When focus last changed, to tell a held arrow key from a single step.
    /// A plain reference box so updating it doesn't re-render the strip.
    @State private var focusClock = FocusClock()

    private final class FocusClock {
        var lastChange = Date.distantPast
    }

    var body: some View {
        let pixelSize = Int(side * displayScale)
        let items = library.filmstripItems(radius: Self.radius, extraBefore: extraBefore, extraAfter: extraAfter)

        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(items) { item in
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
        // The window slides one photo per step with the focused one always in
        // its middle, so a scrollbar can't show where you are on the card —
        // and it visibly twitched back then forward on each step (SwiftUI
        // first holds the old photo in place, then the glide moves on).
        .scrollIndicators(.never)
        .onAppear {
            scrolledID = library.focusedID
        }
        // Scrolled by hand (focus unchanged) near an end: add photos there.
        // The binding keeps the photo at the scroll position in place while
        // the earlier ones are inserted, so the strip doesn't jump.
        .onChange(of: scrolledID) { _, id in
            guard let id, id != library.focusedID,
                  let position = items.firstIndex(where: { $0.id == id })
            else { return }
            if position - items.startIndex < Self.growMargin, items.startIndex > 0 {
                extraBefore += Self.radius
            }
            if items.endIndex - position <= Self.growMargin, items.endIndex < library.visibleItems.count {
                extraAfter += Self.radius
            }
        }
        .onChange(of: library.focusedID) { _, id in
            extraBefore = 0
            extraAfter = 0
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
