//
//  PresetStore.swift
//  rawpreview
//

import AppKit
import Observation

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

    /// What the loupe should apply right now.
    var activePreset: DevelopPreset? {
        isEnabled ? selectedPreset : nil
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

    /// Validates each file, copies the readable ones in and selects the last.
    func importPresets(from urls: [URL]) {
        var failures: [String] = []
        var lastImported: String?
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        } catch {
            loadError = error.localizedDescription
            return
        }

        for url in urls {
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
                failures.append(error.localizedDescription)
            }
        }

        reload()
        if let lastImported { selectedID = lastImported }
        if !failures.isEmpty { loadError = failures.joined(separator: "\n") }
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
