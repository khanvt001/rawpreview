//
//  FilterBar.swift
//  rawpreview
//

import SwiftUI

/// One toggle chip per file extension found in the source, e.g. "NEF 481",
/// a sort menu, and a file-name search box (⌘F).
struct FilterBar: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
                .help("Filter by file type")

            MarkedFilterChip()
            RatingFilterChip()

            Divider().frame(height: 16)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(library.extensionCounts, id: \.ext) { entry in
                        FilterChip(
                            title: entry.ext,
                            count: entry.count,
                            isOn: !library.isExtensionHidden(entry.ext)
                        ) {
                            library.toggleExtension(entry.ext)
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            if !library.hiddenExtensions.isEmpty {
                Button("Show All") {
                    library.showAllExtensions()
                }
                .buttonStyle(.link)
                .font(.callout)
            }

            SortMenu()
            SearchField()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// "↑↓ Capture Date": sort by capture date, file name or file size, either way.
private struct SortMenu: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library

        Menu {
            Picker("Sort By", selection: $library.sortOrder) {
                ForEach(LibraryViewModel.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.inline)
            Picker("Order", selection: $library.sortsAscending) {
                Text(library.sortOrder.directionTitle(ascending: true)).tag(true)
                Text(library.sortOrder.directionTitle(ascending: false)).tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label(library.sortOrder.title, systemImage: library.sortsAscending ? "arrow.up" : "arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.callout)
        .focusable(false)
        .help("Sort by \(library.sortOrder.title.lowercased()), \(library.sortOrder.directionTitle(ascending: library.sortsAscending).lowercased())")
    }
}

private struct SearchField: View {
    @Environment(LibraryViewModel.self) private var library
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var library = library

        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search file names", text: $library.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                // Esc clears; Return hands the keyboard back to the grid.
                .onExitCommand {
                    library.searchText = ""
                    isFocused = false
                }
                .onSubmit { isFocused = false }
                .onChange(of: isFocused) { _, focused in
                    library.isSearchFocused = focused
                }
            if !library.searchText.isEmpty {
                Button {
                    library.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: 200)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1)
            }
        }
        .background {
            // Invisible ⌘F target.
            Button("Find") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .help("Search file names (⌘F)")
    }
}

/// "✓ Marked 12": shows only the files marked for copy (Return / S).
private struct MarkedFilterChip: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        let isOn = library.showsOnlyChecked

        Button {
            library.showsOnlyChecked.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Marked")
                    .fontWeight(.semibold)
                Text(library.checkedIDs.count, format: .number)
                    .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(
                isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isOn ? "Show all files" : "Show only marked files")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "★ 3+" menu: shows only files with at least N stars, or only unrated ones.
private struct RatingFilterChip: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library
        let isOn = library.ratingFilter != nil

        Menu {
            Picker("Rating", selection: $library.ratingFilter) {
                Text("Any Rating").tag(LibraryViewModel.RatingFilter?.none)
                Divider()
                ForEach((1...Rating.maxStars).reversed(), id: \.self) { stars in
                    Text(Self.label(for: .atLeast(Rating(stars))))
                        .tag(LibraryViewModel.RatingFilter?.some(.atLeast(Rating(stars))))
                }
                Divider()
                Text("Unrated").tag(LibraryViewModel.RatingFilter?.some(.unrated))
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                Text(library.ratingFilter.map(Self.label) ?? String(localized: "Rating"))
                    .fontWeight(.semibold)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(
                isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .help("Filter by star rating")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private static func label(for filter: LibraryViewModel.RatingFilter) -> String {
        switch filter {
        case .unrated: String(localized: "Unrated")
        case .atLeast(let rating) where rating.rawValue == Rating.maxStars: String(repeating: "★", count: Rating.maxStars)
        case .atLeast(let rating): String(repeating: "★", count: rating.rawValue) + "+"
        }
    }
}

private struct FilterChip: View {
    let title: String
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(count, format: .number)
                    .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(
                isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary),
                in: Capsule()
            )
            .strikethrough(!isOn)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isOn ? "Hide .\(title) files" : "Show .\(title) files")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
