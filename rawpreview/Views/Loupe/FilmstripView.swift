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

    private let side: CGFloat = 76

    var body: some View {
        let pixelSize = Int(side * displayScale)

        ScrollViewReader { proxy in
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
                        .onTapGesture {
                            library.focusedID = item.id
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: library.focusedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                if let id = library.focusedID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(height: side + 16)
        .background(.bar)
    }
}
