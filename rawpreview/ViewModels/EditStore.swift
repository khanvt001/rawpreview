//
//  EditStore.swift
//  rawpreview
//

import Foundation
import Observation

/// Light adjustments made in the Edit sidebar, per shot: a RAW+JPEG pair
/// shares them, like it shares a rating. Kept for this session only: nothing
/// is written to sidecars yet.
@Observable
final class EditStore {
    /// By shot (`PhotoItem.sidecarURL`).
    private var adjustments: [URL: LightAdjustments] = [:]

    func adjustments(for id: PhotoItem.ID?) -> LightAdjustments {
        id.flatMap { adjustments[PhotoItem.sidecarURL(for: $0)] } ?? LightAdjustments()
    }

    func setAdjustments(_ value: LightAdjustments, for id: PhotoItem.ID) {
        adjustments[PhotoItem.sidecarURL(for: id)] = value.isZero ? nil : value
    }

    func hasAdjustments(_ id: PhotoItem.ID?) -> Bool {
        !adjustments(for: id).isZero
    }

    /// `preset` plus the adjustments of whichever of `items` have any, for
    /// copy and share; `nil` when that applies nothing.
    func exportLook(preset: DevelopPreset?, for items: [PhotoItem]) -> ExportLook? {
        let shots = Set(items.filter(\.kind.isImage).map(\.sidecarURL))
        return ExportLook(preset: preset, adjustments: adjustments.filter { shots.contains($0.key) })
    }

    private struct CombinedKey: Equatable {
        let preset: UUID?
        let light: LightAdjustments
    }

    @ObservationIgnored private var combined: (key: CombinedKey, preset: DevelopPreset?)?

    /// `base` with the photo's adjustments on top, for the renderer. The same
    /// inputs return the same instance, so its `revision` (the render cache
    /// key) only changes when a slider or the preset does.
    func preset(applying base: DevelopPreset?, to id: PhotoItem.ID?) -> DevelopPreset? {
        let light = adjustments(for: id)
        guard !light.isZero else { return base }
        let key = CombinedKey(preset: base?.revision, light: light)
        if let combined, combined.key == key { return combined.preset }
        let preset = DevelopPreset.combining(base, with: light)
        combined = (key, preset)
        return preset
    }
}
