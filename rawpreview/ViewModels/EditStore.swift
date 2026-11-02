//
//  EditStore.swift
//  rawpreview
//

import AppKit
import Observation

/// Light adjustments made in the Edit sidebar, per shot: a RAW+JPEG pair
/// shares them, like it shares a rating. Kept in Application Support, keyed
/// by the shot's path, so they survive quitting and come back when the same
/// card is inserted again. Not written to sidecars: Lightroom would read them
/// as its own develop settings.
@Observable
final class EditStore {
    /// By shot (`PhotoItem.sidecarURL`).
    private var adjustments: [URL: LightAdjustments] = [:]

    nonisolated static let fileURL = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "rawpreview", directoryHint: .isDirectory)
        .appending(path: "Edits.json")

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([String: LightAdjustments].self, from: data) {
            adjustments = Dictionary(
                saved.map { (URL(filePath: $0.key), $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        // A drag in the last half second before quitting would miss the
        // debounced write.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.saveTask != nil else { return }
                self.saveTask?.cancel()
                Self.writeNow(self.snapshot)
            }
        }
    }

    func adjustments(for id: PhotoItem.ID?) -> LightAdjustments {
        id.flatMap { adjustments[PhotoItem.sidecarURL(for: $0)] } ?? LightAdjustments()
    }

    func setAdjustments(_ value: LightAdjustments, for id: PhotoItem.ID) {
        adjustments[PhotoItem.sidecarURL(for: id)] = value.isZero ? nil : value
        scheduleSave()
    }

    func hasAdjustments(_ id: PhotoItem.ID?) -> Bool {
        !adjustments(for: id).isZero
    }

    /// Photo ▸ Copy Edits, waiting to be pasted onto other photos.
    private(set) var copiedAdjustments: LightAdjustments?

    func copyAdjustments(of id: PhotoItem.ID) {
        copiedAdjustments = adjustments(for: id)
    }

    /// Replaces the edits of `items` (a RAW+JPEG pair once) with the copied ones.
    func pasteAdjustments(onto items: [PhotoItem]) {
        guard let copiedAdjustments else { return }
        for item in items where item.kind.isImage {
            setAdjustments(copiedAdjustments, for: item.id)
        }
    }

    /// `preset` plus the adjustments of whichever of `items` have any, for
    /// copy and share; `nil` when that applies nothing.
    func exportLook(preset: DevelopPreset?, for items: [PhotoItem]) -> ExportLook? {
        let shots = Set(items.filter(\.kind.isImage).map(\.sidecarURL))
        return ExportLook(preset: preset, adjustments: adjustments.filter { shots.contains($0.key) })
    }

    /// Slider drags set adjustments many times a second; write once they settle.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = snapshot
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Self.write(snapshot)
            saveTask = nil
        }
    }

    private var snapshot: [String: LightAdjustments] {
        Dictionary(uniqueKeysWithValues: adjustments.map { ($0.key.path(percentEncoded: false), $0.value) })
    }

    @concurrent
    private static func write(_ snapshot: [String: LightAdjustments]) async {
        writeNow(snapshot)
    }

    nonisolated private static func writeNow(_ snapshot: [String: LightAdjustments]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

}
