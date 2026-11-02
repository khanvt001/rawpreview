//
//  PresetInspector.swift
//  rawpreview
//

import SwiftUI
import Combine

/// The sidebar's Presets page: the applied preset (its name opens a menu of
/// every preset) with a before / after switch, a search box, then a grid of
/// preset names, imported ones first and the built-in collection in
/// collapsible categories. Preset files or folders dropped on it are imported.
struct PresetInspector: View {
    @Environment(PresetStore.self) private var store
    @Environment(LibraryViewModel.self) private var library
    @State private var query = ""
    @State private var isDropTargeted = false
    /// Tiles show the focused photo through each preset.
    @AppStorage("presetPreviews") private var showsPreviews = true
    /// The focused photo, small, for the tiles to render from.
    @State private var source: PresetTile.Source?
    @State private var sourceRevision = 0
    @AppStorage(ProcessingSource.defaultsKey) private var sourceSetting = ProcessingSource.embedded.rawValue
    @AppStorage(ProcessingSource.fallbackKey) private var fallbackData = Data()

    var body: some View {
        VStack(spacing: 0) {
            CurrentPresetCard()
                .padding(12)
            Divider()
            PresetSearchField(query: $query)
                .padding(8)
            presetGrid
            Divider()
            bottomBar
        }
        .onReceive(NotificationCenter.default.publisher(for: DevelopService.sourceReady).receive(on: DispatchQueue.main)) { notification in
            if let url = notification.object as? URL, url == source?.url { sourceRevision += 1 }
        }
        .task(id: SourceKey(photo: showsPreviews ? library.focusedID : nil, source: sourceSetting,
                            fallbacks: fallbackData, revision: sourceRevision)) {
            guard showsPreviews, let item = library.focusedItem, item.kind.isImage else {
                source = nil
                return
            }
            let configuration = ProcessingConfiguration(source: ProcessingSource(rawValue: sourceSetting) ?? .embedded,
                                                        embeddedFallbacks: ProcessingConfiguration.decodeFallbacks(fallbackData))
            let resolved = await PhotoSourceResolver.resolve(item.url, processing: configuration)
            guard !Task.isCancelled else { return }
            source = PresetTile.Source(url: resolved, revision: sourceRevision)
        }
        // Never leave the loupe stuck on a hovered preset.
        .onDisappear { store.hoveredID = nil }
        .dropDestination(for: URL.self) { urls, _ in
            store.importPresets(from: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .alert(
            "Preset Problem",
            isPresented: Binding(
                get: { store.loadError != nil },
                set: { if !$0 { store.loadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.loadError ?? "")
        }
    }

    private struct SourceKey: Equatable {
        let photo: PhotoItem.ID?
        let source: String
        let fallbacks: Data
        let revision: Int
    }

    private var presetGrid: some View {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let imported = matching(store.presets)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
                    spacing: 6,
                    // An open category's name stays at the top while its presets scroll.
                    pinnedViews: [.sectionHeaders]
                ) {
                    if !searching {
                        Section {
                            tile(nil)
                            ForEach(imported) { tile($0) }
                            if imported.isEmpty {
                                ImportTile { store.chooseAndImport() }
                            }
                        } header: {
                            if !imported.isEmpty {
                                GridHeader(title: String(localized: "Imported"), count: imported.count)
                            }
                        }
                    } else if !imported.isEmpty {
                        Section {
                            ForEach(imported) { tile($0) }
                        } header: {
                            GridHeader(title: String(localized: "Imported"), count: imported.count)
                        }
                    }

                    ForEach(store.builtInCategories) { category in
                        let presets = matching(category.presets)
                        if !presets.isEmpty {
                            // Searching shows every match; otherwise categories open and close.
                            let isExpanded = searching || store.expandedCategories.contains(category.name)
                            Section {
                                if isExpanded {
                                    ForEach(presets) { tile($0) }
                                }
                            } header: {
                                GridHeader(
                                    title: category.name,
                                    count: presets.count,
                                    isExpanded: searching ? nil : isExpanded
                                ) {
                                    toggle(category.name)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            // `.hidden` still shows legacy scroll bars (mouse attached, or
            // "Always show scroll bars"); `.never` hides them regardless.
            .scrollIndicators(.never)
            .overlay {
                if searching, matching(store.presets + store.builtInCategories.flatMap(\.presets)).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .onAppear {
                if let category = store.category(of: store.selectedID) {
                    store.expandedCategories.insert(category.name)
                }
                if let id = store.selectedID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // [ / ] and the title menu can pick a preset that's scrolled away.
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id) }
            }
        }
    }

    private func tile(_ preset: DevelopPreset?) -> some View {
        PresetTile(
            preset: preset,
            isSelected: store.selectedID == preset?.id,
            source: showsPreviews ? source : nil,
            amount: store.amount
        ) {
            store.selectedID = preset?.id
        }
        .id(preset?.id ?? "original")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Import Presets…", systemImage: "plus") { store.chooseAndImport() }
                .help("Import Lightroom presets (.lrtemplate / .xmp), or folders of them. You can also drop them here.")
            Button("Remove Preset", systemImage: "minus") {
                if let preset = store.selectedPreset { store.remove(preset) }
            }
            .disabled(store.selectedPreset.map(store.isBuiltIn) ?? true)
            .help("Move the selected imported preset to the Trash")
            Spacer()
            Toggle(isOn: $showsPreviews) {
                Label("Preview Thumbnails", systemImage: "photo")
            }
            .toggleStyle(.button)
            .help("Show the photo through each preset")
            Button("Show Presets Folder", systemImage: "folder") { store.revealFolder() }
                .help("Show imported presets in Finder")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .focusable(false)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func matching(_ presets: [DevelopPreset]) -> [DevelopPreset] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return presets }
        return presets.filter { $0.title.localizedStandardContains(text) }
    }

    private func toggle(_ category: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            if store.expandedCategories.contains(category) {
                store.expandedCategories.remove(category)
            } else {
                store.expandedCategories.insert(category)
            }
        }
    }
}

/// "Import…" in the grid until there are imported presets: the bar's +
/// button is easy to miss.
private struct ImportTile: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label("Import…", systemImage: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isHovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help("Import Lightroom presets (.lrtemplate / .xmp), or folders of them. You can also drop them on this sidebar.")
    }
}

/// One preset as a selectable cell (or "None", for `nil`): the focused photo
/// through it, when previews are on, above its name. Resting the pointer on
/// it previews it on the photo.
private struct PresetTile: View {
    struct Source: Equatable {
        let url: URL
        let revision: Int
    }

    let preset: DevelopPreset?
    let isSelected: Bool
    let source: Source?
    let amount: Double
    let select: () -> Void

    @Environment(PresetStore.self) private var store
    @Environment(EditStore.self) private var edits
    @Environment(LibraryViewModel.self) private var library
    @AppStorage(ProcessingSource.defaultsKey) private var sourceSetting = ProcessingSource.embedded.rawValue
    @AppStorage(ProcessingSource.fallbackKey) private var fallbackData = Data()
    @State private var isHovered = false
    @State private var thumbnail: CGImage?
    @State private var hoverTask: Task<Void, Never>?

    private struct RenderKey: Equatable {
        let source: Source?
        let preset: UUID?
        let amount: Double
        let light: LightAdjustments
        let sourceSetting: String
        let fallbacks: Data
    }

    var body: some View {
        Button {
            hoverTask?.cancel()
            store.hoveredID = nil
            select()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if source != nil {
                    thumbnailView
                }
                label
            }
            .padding(source == nil ? 0 : 4)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(background)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            isHovered = hovering
            hover(hovering)
        }
        .help(preset.map { [$0.title, $0.summary].compactMap(\.self).joined(separator: "\n") } ?? String(localized: "The photo as shot"))
        .onDisappear {
            hover(false)
        }
        .task(id: RenderKey(source: source, preset: preset?.revision, amount: amount,
                            light: edits.adjustments(for: library.focusedID), sourceSetting: sourceSetting, fallbacks: fallbackData)) {
            await render()
        }
    }

    private var thumbnailView: some View {
        Color.black.opacity(0.2)
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func render() async {
        guard let source else {
            thumbnail = nil
            return
        }
        let configuration = ProcessingConfiguration(source: ProcessingSource(rawValue: sourceSetting) ?? .embedded,
                                                      embeddedFallbacks: ProcessingConfiguration.decodeFallbacks(fallbackData))
        let state = DevelopState(processing: configuration, preset: preset?.atAmount(amount),
                                 light: edits.adjustments(for: library.focusedID))
        do {
            let rendered = try await DevelopService.tile(url: source.url, state: state)
            if !Task.isCancelled { thumbnail = rendered }
        } catch {
            if !Task.isCancelled { thumbnail = nil }
        }
    }

    /// Waits a moment so sweeping across the grid doesn't flash every preset.
    private func hover(_ hovering: Bool) {
        hoverTask?.cancel()
        guard let id = preset?.id else { return }
        if hovering {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                store.hoveredID = id
            }
        } else if store.hoveredID == id {
            store.hoveredID = nil
        }
    }

    private var label: some View {
            HStack(spacing: 4) {
                Text(preset?.title ?? String(localized: "None"))
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let preset, preset.compatibility.hasInvalidData {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if preset?.isMonochrome == true {
                    Text("B&W")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, source == nil ? 8 : 4)
            .frame(maxWidth: .infinity, minHeight: source == nil ? 36 : 28, alignment: .leading)
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        return isHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quinary)
    }
}

private struct GridHeader: View {
    let title: String
    let count: Int
    /// `nil`: not collapsible.
    var isExpanded: Bool?
    var toggle: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                if let isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                }
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                // Only collapsible headers look (and highlight) like a row you can click.
                if isExpanded != nil {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quinary))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isExpanded == nil)
        .onHover { isHovered = $0 }
        .padding(.vertical, 3)
        // Opaque around the rounded row, so presets scrolling under a pinned
        // header don't show through.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// What the preset's settings map to. The header above the grid doesn't
/// scroll, so a long list scrolls inside a capped height instead of pushing
/// the inspector taller than the window.
private struct CompatibilityDetails: View {
    let preset: DevelopPreset

    private static let maxHeight: CGFloat = 120
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                if !preset.compatibility.labels(for: .supported).isEmpty {
                    Text("Applied: \(preset.compatibility.labels(for: .supported).joined(separator: ", "))")
                }
                if !preset.compatibility.labels(for: .approximate).isEmpty {
                    Text("Approximate: \(preset.compatibility.labels(for: .approximate).joined(separator: ", "))")
                }
                if !preset.unsupportedSettings.isEmpty {
                    Text("Not applied: \(preset.unsupportedSettings.joined(separator: ", "))").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, Self.maxHeight))
    }
}

/// What's applied right now: its name opens a menu of every preset; the
/// switch shows before / after.
private struct CurrentPresetCard: View {
    @Environment(PresetStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Menu {
                        PresetMenuItems()
                    } label: {
                        HStack(spacing: 4) {
                            Text(store.selectedPreset?.title ?? String(localized: "No Preset"))
                                .font(.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .focusable(false)
                    .help("Choose a preset")

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Show Preset", isOn: $store.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(store.selectedPreset == nil)
                    .focusable(false)
                    .help("Before / after (\\)")
            }

            if let preset = store.selectedPreset {
                HStack(spacing: 8) {
                    Text("Amount")
                    Slider(value: $store.amount, in: 0...1)
                        .controlSize(.small)
                        // A focused slider takes ← → for itself, which
                        // stops them moving between photos.
                        .focusable(false)
                    Text("\(Int((store.amount * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 2)
                .disabled(!store.isEnabled)
                .help("Scales the preset's supported adjustments. Light edits are deltas added to the preset values.")

                if let summary = preset.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !preset.unsupportedSettings.isEmpty {
                    if preset.compatibility.hasInvalidData {
                        Label("Some preset values are invalid. See compatibility details.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help(preset.compatibility.details)
                    } else {
                        Label("Some preset components aren't applied. See compatibility details.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(preset.compatibility.details)
                    }
                }
                DisclosureGroup("Preset Compatibility") {
                    CompatibilityDetails(preset: preset)
                }
                .font(.caption)
                HStack {
                    Text("Approximate preview · [ ] previous / next")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear") { store.selectedID = nil }
                        .buttonStyle(.link)
                        .font(.caption)
                        .focusable(false)
                }
            } else {
                Text("Preset previews are approximate. Select a preset to review compatibility.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // Capped like the summary: unbounded, the window's minimum
                    // size is measured at a narrow width and grows past the screen.
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        guard let preset = store.selectedPreset else { return String(localized: "Choose a preset below to preview it") }
        let source = store.category(of: preset.id)?.name ?? String(localized: "Imported")
        return store.isEnabled ? source : String(localized: "\(source) · showing original")
    }
}

/// Every preset as checkmark items: imported ones, then one submenu per category.
private struct PresetMenuItems: View {
    @Environment(PresetStore.self) private var store

    var body: some View {
        Toggle("None", isOn: selection(nil))
        if !store.presets.isEmpty {
            Section("Imported") {
                ForEach(store.presets) { preset in
                    Toggle(preset.title, isOn: selection(preset.id))
                }
            }
        }
        Section("Built-in") {
            ForEach(store.builtInCategories) { category in
                Menu(category.name) {
                    ForEach(category.presets) { preset in
                        Toggle(preset.title, isOn: selection(preset.id))
                    }
                }
            }
        }
        Divider()
        Button("Import Presets…") { store.chooseAndImport() }
    }

    private func selection(_ id: String?) -> Binding<Bool> {
        Binding(
            get: { store.selectedID == id },
            set: { isOn in
                guard isOn else { return }
                store.selectedID = id
                // Open its category so the grid can scroll to it.
                if let category = store.category(of: id) {
                    store.expandedCategories.insert(category.name)
                }
            }
        )
    }
}

/// Like the grid's file-name search: Esc clears, Return hands the keyboard
/// back to the photos, and shortcuts pause while it's focused.
///
/// Takes the keyboard only when clicked. AppKit hands focus to the first
/// text field when the sidebar appears, which silently stopped the arrow
/// keys moving between photos.
private struct PresetSearchField: View {
    @Environment(LibraryViewModel.self) private var library
    @Binding var query: String
    @FocusState private var isFocused: Bool
    /// The pointer is over the field, so focus arriving now is a click.
    @State private var isHovered = false
    /// Unasked focus was already handed back since the field appeared.
    @State private var hasDeflected = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search presets", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand {
                    query = ""
                    isFocused = false
                }
                .onSubmit { isFocused = false }
                .onChange(of: isFocused) { _, focused in
                    // Only focus the photos, which also takes it from here:
                    // clearing `isFocused` as well made two competing moves,
                    // and AppKit handed focus straight back, forever. Once
                    // per appearance, so it can never ping-pong.
                    if focused, !isHovered, !hasDeflected {
                        hasDeflected = true
                        library.returnKeyFocusToPhotos()
                        return
                    }
                    library.isSearchFocused = focused
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Clear search")
            }
        }
        .onHover { isHovered = $0 }
        .onAppear { hasDeflected = false }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1)
            }
        }
    }
}
