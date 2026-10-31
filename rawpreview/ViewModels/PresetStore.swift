//
//  PresetStore.swift
//  rawpreview
//

import AppKit
import Observation

/// Develop presets the user has imported, and which one the loupe previews.
///
/// Imported files are copied into Application Support, so presets stay
/// available after the card or folder they came from is gone.
@Observable
final class PresetStore {
    private(set) var presets: [DevelopPreset] = []

    /// The chosen preset, remembered across launches.
    var selectedID: String? = UserDefaults.standard.string(forKey: "selectedPresetID") {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "selectedPresetID")
            if selectedID != nil { isEnabled = true }
        }
    }

    /// Before / after (\): off shows photos as shot without forgetting the
    /// chosen preset.
    var isEnabled = true

    /// Files that couldn't be imported or loaded, for an alert.
    var loadError: String?

    var selectedPreset: DevelopPreset? {
        presets.first { $0.id == selectedID }
    }

    /// What the loupe should apply right now.
    var activePreset: DevelopPreset? {
        isEnabled ? selectedPreset : nil
    }

    static let folder = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "rawpreview", directoryHint: .isDirectory)
        .appending(path: "Presets", directoryHint: .isDirectory)

    init() {
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
