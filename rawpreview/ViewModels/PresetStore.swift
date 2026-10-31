//
//  PresetStore.swift
//  rawpreview
//

import AppKit
import Observation
import UniformTypeIdentifiers

/// Develop presets (built-in and imported), and which one the loupe previews.
///
/// Built-in presets come from `BuiltInPresets.json` in the app bundle,
/// generated from the Emulsion Presets collection by
/// `scripts/build_builtin_presets.py`. Imported files are copied into
/// Application Support, so they stay available after the card or folder they
/// came from is gone.
@Observable
final class PresetStore {
    struct Category: Identifiable {
        let name: String
        let presets: [DevelopPreset]
        var id: String { name }
    }

    let builtInCategories: [Category]
    private let builtInByID: [String: DevelopPreset]
    /// The user's imported presets.
    private(set) var presets: [DevelopPreset] = []

    /// The chosen preset. Deliberately not remembered: a new session starts
    /// with photos as shot, so a card is never judged through yesterday's look.
    var selectedID: String? {
        didSet {
            if selectedID != nil { isEnabled = true }
        }
    }

    /// Before / after (\): off shows photos as shot without forgetting the
    /// chosen preset.
    var isEnabled = true

    /// Files that couldn't be imported or loaded, for an alert.
    var loadError: String?

    var selectedPreset: DevelopPreset? {
        guard let selectedID else { return nil }
        return builtInByID[selectedID] ?? presets.first { $0.id == selectedID }
    }

    func isBuiltIn(_ preset: DevelopPreset) -> Bool {
        builtInByID[preset.id] != nil
    }

    /// Built-in category containing `id`, if any.
    func category(of id: String?) -> Category? {
        guard let id else { return nil }
        return builtInCategories.first { $0.presets.contains { $0.id == id } }
    }

    /// Built-in categories open in the Presets sidebar; remembered across launches.
    var expandedCategories: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "expandedPresetCategories") ?? []) {
        didSet { UserDefaults.standard.set(expandedCategories.sorted(), forKey: "expandedPresetCategories") }
    }

    /// [ / ]: the previous / next preset in sidebar order (imported first,
    /// then each category), opening its category so the sidebar can show it.
    func selectAdjacent(_ offset: Int) {
        let order = presets + builtInCategories.flatMap(\.presets)
        guard !order.isEmpty else { return }
        let index = order.firstIndex { $0.id == selectedID }.map { $0 + offset } ?? (offset > 0 ? 0 : order.count - 1)
        let next = order[min(max(index, 0), order.count - 1)]
        selectedID = next.id
        if let category = category(of: next.id) {
            expandedCategories.insert(category.name)
        }
    }

    private struct BuiltInFile: Decodable {
        struct Category: Decodable {
            let name: String
            let presets: [Preset]
        }

        struct Preset: Decodable {
            let name: String
            let description: String
            let settings: [String: PresetValue]
        }

        let categories: [Category]
    }

    private static func loadBuiltIns() -> [Category] {
        guard let url = Bundle.main.url(forResource: "BuiltInPresets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(BuiltInFile.self, from: data)
        else { return [] }
        return file.categories.map { category in
            Category(name: category.name, presets: category.presets.map { preset in
                DevelopPreset(
                    id: "builtin/\(category.name)/\(preset.name)",
                    title: preset.name,
                    summary: preset.description.isEmpty ? nil : preset.description,
                    settings: preset.settings
                )
            })
        }
    }

    /// How strongly the chosen preset is applied, 0…1, mixed with the photo
    /// as shot; remembered across launches.
    var amount: Double = UserDefaults.standard.object(forKey: "presetAmount") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(amount, forKey: "presetAmount") }
    }

    @ObservationIgnored private var applied: (id: UUID, amount: Double, preset: DevelopPreset)?

    /// The chosen preset at `amount`, for previews and exports. The same
    /// instance while neither changes, so its revision (the render cache
    /// key) stays put.
    var appliedPreset: DevelopPreset? {
        guard let selected = selectedPreset else { return nil }
        let amount = amount
        if let applied, applied.id == selected.revision, applied.amount == amount {
            return applied.preset
        }
        let preset = selected.atAmount(amount)
        applied = (selected.revision, amount, preset)
        return preset
    }

    /// What the loupe should apply right now.
    var activePreset: DevelopPreset? {
        isEnabled ? appliedPreset : nil
    }

    static let folder = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "rawpreview", directoryHint: .isDirectory)
        .appending(path: "Presets", directoryHint: .isDirectory)

    init() {
        // Left behind by builds that remembered the selection.
        UserDefaults.standard.removeObject(forKey: "selectedPresetID")
        builtInCategories = Self.loadBuiltIns()
        builtInByID = Dictionary(
            builtInCategories.flatMap(\.presets).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        var failures: [String] = []
        presets = files
            .filter { DevelopPreset.fileExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                do {
                    return try DevelopPreset.load(from: url)
                } catch {
                    failures.append(error.localizedDescription)
                    return nil
                }
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if selectedPreset == nil { selectedID = nil }
        if !failures.isEmpty { loadError = failures.joined(separator: "\n") }
    }

    /// Asks for preset files or folders of them (a downloaded preset pack),
    /// then imports them. Used by the sidebar, the title menu and File menu.
    func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = DevelopPreset.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose Lightroom presets (.lrtemplate or .xmp), or folders containing them.")
        guard panel.runModal() == .OK else { return }
        importPresets(from: panel.urls)
    }

    /// Validates each file (folders are searched, subfolders included),
    /// copies the readable ones in and selects the last.
    func importPresets(from urls: [URL]) {
        var failures: [String] = []
        /// Files found inside folders that aren't presets (camera profiles,
        /// read-me files…): counted, not listed one by one.
        var skippedInFolders = 0
        var lastImported: String?
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        } catch {
            loadError = error.localizedDescription
            return
        }

        var files: [(url: URL, fromFolder: Bool)] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                files += Self.presetFiles(in: url).map { ($0, true) }
            } else {
                files.append((url, false))
            }
        }

        for (url, fromFolder) in files {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try DevelopPreset.load(from: url)
                let destination = Self.folder.appending(path: url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
                lastImported = destination.lastPathComponent
            } catch {
                if fromFolder {
                    skippedInFolders += 1
                } else {
                    failures.append(error.localizedDescription)
                }
            }
        }

        reload()
        if let lastImported { selectedID = lastImported }
        if lastImported == nil, failures.isEmpty {
            failures.append(String(localized: "No Lightroom develop presets were found."))
        }
        if skippedInFolders > 0, !failures.isEmpty || lastImported == nil {
            failures.append(String(localized: "\(skippedInFolders) other files in the folders weren't develop presets."))
        }
        if !failures.isEmpty { loadError = failures.joined(separator: "\n") }
    }

    private static func presetFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { DevelopPreset.fileExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path(percentEncoded: false).localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending }
    }

    func remove(_ preset: DevelopPreset) {
        let url = Self.folder.appending(path: preset.id)
        // Trash, not delete: the user may have no other copy.
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            loadError = error.localizedDescription
        }
        reload()
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Self.folder])
    }
}
