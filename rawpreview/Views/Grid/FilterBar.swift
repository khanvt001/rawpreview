//
//  FilterBar.swift
//  rawpreview
//

import SwiftUI

/// One toggle chip per file extension found in the source, e.g. "NEF 481".
struct FilterBar: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
                .help("Filter by file type")

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
